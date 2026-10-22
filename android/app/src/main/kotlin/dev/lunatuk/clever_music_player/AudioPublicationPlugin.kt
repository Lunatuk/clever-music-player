package dev.lunatuk.clever_music_player

import android.content.Context
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.system.Os
import android.system.OsConstants
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Separate admission (private journal only), provider IO, and acknowledgement.
 * Music is never opened for write during recovery or deleted by this API. */
class AudioPublicationPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val canceller = ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(1), ThreadPoolExecutor.DiscardPolicy())
    private val active = AtomicReference<Request?>(null)
    private var detached = false
    private class Busy : Exception()
    private class Request(val id: Int, val check: Boolean) {
        val cancelled = AtomicBoolean(false)
        val signal = CancellationSignal()
        val descriptors: MutableSet<ParcelFileDescriptor> = java.util.Collections.newSetFromMap(ConcurrentHashMap<ParcelFileDescriptor, Boolean>())
        var stage = 0
    }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dev.lunatuk.clever_music_player/audio_publication")
        channel.setMethodCallHandler(this)
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val methods = setOf("prepareAudioPublication", "publishPreparedAudio", "reconcileAudioPublication",
            "acknowledgeAudioPublication", "listAudioPublications", "checkAudioPublication", "cancelAudioPublication", "cancelAudioPublicationCheck")
        if (call.method !in methods) { result.notImplemented(); return }
        val number = call.argument<Any>("requestId")
        val id = when (number) { is Int -> number.toLong(); is Long -> number; else -> null }
        if (id == null || id !in 1..Int.MAX_VALUE.toLong()) {
            result.error("invalid_request", "Invalid request ID", null); return
        }
        if (call.method.startsWith("cancel")) {
            active.get()?.takeIf { it.id == id.toInt() && it.check == (call.method == "cancelAudioPublicationCheck") }?.let(::cancel)
            result.success(null); return
        }
        if (detached) { result.error("closed", "Publication closed", null); return }
        val check = call.method == "checkAudioPublication"
        val binding: AudioPublicationBinding?
        val tree: Uri
        try {
            tree = Uri.parse(call.argument<String>("tree") ?: error("invalid_tree"))
            require(validTree(tree))
            binding = if (check || call.method == "listAudioPublications") null else binding(call, tree)
        } catch (_: Exception) { result.error("invalid_request", "Invalid publication", null); return }
        val request = Request(id.toInt(), check)
        if (!active.compareAndSet(null, request)) {
            result.success(response(request, "busy")); return
        }
        worker.execute {
            val response = try {
                withJournal { journal ->
                    val docs = Documents(context, tree, request)
                    val publication = AudioPublication(journal, docs)
                    if (check) checkDestination(request, tree, journal, publication)
                    else if (call.method == "listAudioPublications") {
                        request.stage = 1
                        response(request, "pending") + mapOf("operations" to journal.all().filter {
                            !it.first().binding.probe && it.first().binding.tree == tree.toString()
                        }.map { it.first().binding.intent })
                    } else {
                        val b = binding!!
                        when (call.method) {
                            "prepareAudioPublication" -> { request.stage = 2; publication.prepare(b); response(request, "prepared") }
                            "acknowledgeAudioPublication" -> {
                                publication.acknowledge(b, call.argument<String>("document") ?: error("missing_document"))
                                request.stage = 6
                                response(request, "acknowledged")
                            }
                            else -> {
                                val ready = if (call.method == "reconcileAudioPublication") {
                                    publication.reconcile(b) { request.cancelled.get() }
                                } else publication.publish(b, source = {
                                    privateSource(call.argument<String>("sourcePath") ?: error("missing_source"), b.size, request)
                                }) { request.cancelled.get() }
                                request.stage = 6
                                response(request, "published") + mapOf("document" to ready.uri!!,
                                    "sizeBytes" to b.size, "digest" to b.digest, "intent" to b.intent)
                            }
                        }
                    }
                }
            } catch (error: Exception) { response(request, status(error, request)) }
            finally { request.descriptors.toList().forEach { runCatching { it.close() } }; request.descriptors.clear() }
            active.compareAndSet(request, null)
            main.post { result.success(response) }
        }
    }
    private fun binding(call: MethodCall, tree: Uri): AudioPublicationBinding {
        val size = when (val value = call.argument<Any>("sizeBytes")) { is Int -> value.toLong(); is Long -> value; else -> error("size") }
        val b = AudioPublicationBinding(call.argument<String>("resource")!!, call.argument<String>("publicationId")!!,
            tree.toString(), call.argument<String>("intent")!!, size, call.argument<String>("digest")!!,
            call.argument<String>("container")!!, call.argument<String>("owner")!!)
        val intent = JSONObject(b.intent)
        require(intent.getInt("version") == 1 && intent.getString("publicationId") == b.id &&
            intent.getLong("sizeBytes") == b.size && intent.getString("sha256") == b.digest &&
            intent.getString("container") == b.container && intent.getLong("jobId") > 0 && intent.getLong("folderId") > 0)
        return b
    }
    private fun response(request: Request, status: String): Map<String, Any> =
        mapOf("requestId" to request.id, "status" to
            if (request.check && status !in setOf("ready", "cancelled", "accessDenied", "unsupported", "busy", "retained", "io")) "io" else status,
            "stage" to request.stage) +
            if (request.check) mapOf("verifiedBytes" to 0, "recovered" to 0, "retained" to 0) else emptyMap()
    private fun status(error: Exception, request: Request): String = when {
        error is Busy -> "busy"
        request.cancelled.get() || error is CancellationException -> "cancelled"
        error is AudioPublicationNeedsReconciliation -> "needsReconciliation"
        error is AudioPublicationOwnershipLost -> "ownershipLost"
        error is AudioPublicationCollision -> "collision"
        error is AudioPublicationQuota -> "quotaExceeded"
        error is ContentChangedException -> "changed"
        error is SecurityException -> "accessDenied"
        generateSequence<Throwable>(error) { it.cause }.take(8).any {
            it is android.system.ErrnoException && it.errno in setOf(OsConstants.ENOSPC, OsConstants.EDQUOT)
        } -> "noSpace"
        else -> "io"
    }
    private fun cancel(request: Request) {
        if (!request.cancelled.compareAndSet(false, true)) return
        canceller.execute {
            runCatching { request.signal.cancel() }
            request.descriptors.toList().forEach { runCatching { it.close() } }
        }
    }
    private fun <T> withJournal(action: (AudioPublicationDiskJournal) -> T): T {
        val directory = File(context.filesDir.canonicalFile, "audio-publications-v1")
        val created = if (directory.exists()) false else directory.mkdir().also { require(it) }
        require(directory.canonicalFile == directory.absoluteFile && directory.isDirectory)
        RandomAccessFile(File(directory, "owner.lock"), "rw").use { file ->
            val lock = try { file.channel.tryLock() } catch (_: java.nio.channels.OverlappingFileLockException) { null } ?: throw Busy()
            lock.use {
                val journal = AudioPublicationDiskJournal(directory)
                journal.initialize(created)
                return action(journal)
            }
        }
    }
    private fun privateSource(path: String, size: Long, request: Request): java.io.InputStream {
        val file = File(path)
        val parent = context.filesDir.canonicalFile
        require(file.isAbsolute && file.canonicalFile == file.absoluteFile && file.canonicalPath.startsWith(parent.path + File.separator))
        // O_CLOEXEC entered the public SDK in 27. On 24-26 the short-lived
        // raw descriptor is closed immediately after validation/dup; this
        // backend does not execute subprocesses. No hidden fcntl API calls.
        val closeOnExec = if (android.os.Build.VERSION.SDK_INT >= 27) OsConstants.O_CLOEXEC else 0
        val fd = Os.open(path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or closeOnExec, 0)
        val opened = try {
            val stat = Os.fstat(fd)
            require(OsConstants.S_ISREG(stat.st_mode) && stat.st_size == size)
            ParcelFileDescriptor.dup(fd)
        } finally { Os.close(fd) }
        request.descriptors.add(opened)
        return object : java.io.FilterInputStream(ParcelFileDescriptor.AutoCloseInputStream(opened)) {
            override fun close() { try { super.close() } finally { request.descriptors.remove(opened) } }
        }
    }
    private fun checkDestination(request: Request, tree: Uri, journal: AudioPublicationDiskJournal,
        publication: AudioPublication): Map<String, Any> {
        var recovered = 0
        var current: AudioPublicationBinding? = null
        fun response(status: String, retained: Int = 0, bytes: Int = 0) = this@AudioPublicationPlugin.response(request, status) +
            mapOf("verifiedBytes" to bytes, "recovered" to recovered, "retained" to retained)
        try {
            for (records in journal.all().filter { it.first().binding.probe && it.first().binding.tree == tree.toString() }) {
                if (request.cancelled.get()) throw CancellationException()
                publication.cleanupProbe(records.first().binding)
                recovered++
            }
            request.stage = 2
            val id = UUID.randomUUID().toString().replace("-", "") + UUID.randomUUID().toString().replace("-", "")
            val bytes = AudioPublicationBinding.probeBytes(id)
            val hash = StreamingContentFingerprint.read(ByteArrayInputStream(bytes), 4096) { false }.digest
            val b = AudioPublicationBinding("0".repeat(64), id, tree.toString(), "cmp-audio-publication-probe-v1",
                4096, hash, "mp3", id, probe = true)
            current = b
            publication.prepare(b)
            val source = File(context.filesDir.canonicalFile, "publication-probe-$id.part")
            require(source.createNewFile())
            try {
                java.io.FileOutputStream(source).use { it.write(bytes); it.fd.sync() }
                publication.publish(b, { privateSource(source.path, 4096, request) }) { request.cancelled.get() }
            } finally { require(source.delete()) }
            request.stage = 6
            publication.cleanupProbe(b)
            current = null
            return response(if (request.cancelled.get()) "cancelled" else "ready", bytes = 4096)
        } catch (error: Exception) {
            // Both source and output have drained before attempting test cleanup.
            if (current != null) {
                try { publication.cleanupProbe(current) } catch (_: Exception) { /* retained below */ }
            }
            val retained = journal.all().count { group -> group.first().binding.probe && group.first().binding.tree == tree.toString() }
            if (retained > 0) return response("retained", retained)
            return response(when (status(error, request)) {
                "accessDenied" -> "accessDenied"; "cancelled" -> "cancelled"; "busy" -> "busy"; else -> "io"
            })
        }
    }
    private class Documents(private val context: Context, private val tree: Uri, private val request: Request) : AudioPublicationDocuments {
        private val resolver get() = context.contentResolver
        private val rootId = DocumentsContract.getTreeDocumentId(tree)
        private val root = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
        private val fresh = hashSetOf<String>()
        private var attempted = false
        override val createAttempted: Boolean get() = attempted
        private data class Child(val id: String, val name: String, val mime: String?, val size: Long?, val modified: Long?)
        private fun children(cleanup: Boolean = false, requireCreate: Boolean = false): List<Child> {
            if (!resolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission && it.isWritePermission }) throw SecurityException()
            val signal = if (cleanup) null else request.signal
            resolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_FLAGS), null, null, null, signal).use { cursor ->
                if (cursor == null || !cursor.moveToFirst() || cursor.getString(0) != DocumentsContract.Document.MIME_TYPE_DIR) throw IOException()
                if (requireCreate && cursor.getInt(1) and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE == 0) throw IOException()
            }
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, rootId)
            val found = ArrayList<Child>()
            resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED), null, null, null, signal).use { cursor ->
                if (cursor == null) throw IOException()
                var characters = 0
                while (cursor.moveToNext()) {
                    if (!cleanup) signal?.throwIfCanceled()
                    if (found.size >= 10000) throw IOException()
                    val id = cursor.getString(0); val name = cursor.getString(1)
                    if (id.length > 8192 || name.length > 255 || characters > 8 * 1024 * 1024 - id.length - name.length) throw IOException()
                    characters += id.length + name.length
                    fun number(index: Int) = if (cursor.isNull(index)) null else cursor.getLong(index).takeIf { it >= 0 }
                    found.add(Child(id, name, cursor.getString(2), number(3), number(4)))
                }
            }
            return found
        }
        private fun validate(record: AudioPublicationRecord, cleanup: Boolean = false, missing: Boolean = false): Pair<Uri, Child>? {
            require(record.binding.tree == tree.toString())
            val uri = Uri.parse(record.uri ?: error("missing_uri"))
            require(uri.scheme == "content" && uri.authority == tree.authority && uri.query == null && uri.fragment == null &&
                uri.pathSegments.size == 4 && uri.pathSegments[0] == "tree" && uri.pathSegments[2] == "document" &&
                DocumentsContract.getTreeDocumentId(uri) == rootId)
            val id = DocumentsContract.getDocumentId(uri)
            require(id != rootId && !id.contains('\u0000'))
            val matches = children(cleanup).filter { it.id == id }
            if (missing && matches.isEmpty()) return null
            if (matches.size != 1 || matches.single().name != record.binding.name || matches.single().mime == DocumentsContract.Document.MIME_TYPE_DIR) throw ContentChangedException()
            return DocumentsContract.buildDocumentUriUsingTree(tree, id) to matches.single()
        }
        override fun create(binding: AudioPublicationBinding): String {
            request.stage = 3
            val before = children(requireCreate = true)
            if (before.any { it.name == binding.name }) throw AudioPublicationCollision()
            if (request.cancelled.get()) throw CancellationException()
            val mime = when (binding.container) { "mp3" -> "audio/mpeg"; "m4a" -> "audio/mp4"; else -> "audio/flac" }
            attempted = true
            val uri = DocumentsContract.createDocument(resolver, root, mime, binding.name) ?: throw IOException()
            val record = AudioPublicationRecord(binding, AudioPublicationPhase.DOCUMENT, uri.toString(), true)
            // Drain the accepted create even after cancellation. Its new URI
            // must be validated/recorded before cancellation prevents writing.
            val checked = validate(record, cleanup = true) ?: throw IOException()
            if (before.any { it.id == checked.second.id }) throw AudioPublicationCollision()
            fresh.add(checked.first.toString())
            return checked.first.toString()
        }
        private fun descriptor(uri: Uri, write: Boolean, cleanup: Boolean = false): ParcelFileDescriptor {
            val fd = resolver.openFileDescriptor(uri, if (write) "w" else "r", if (cleanup) null else request.signal) ?: throw IOException()
            if (!cleanup) request.descriptors.add(fd)
            if (!cleanup && request.cancelled.get()) { request.descriptors.remove(fd); fd.close(); throw CancellationException() }
            return fd
        }
        override fun output(record: AudioPublicationRecord): java.io.OutputStream {
            request.stage = 4
            val uri = validate(record)!!.first
            require(fresh.remove(uri.toString())) // exactly once, only live create
            val fd = descriptor(uri, true)
            return object : java.io.FilterOutputStream(ParcelFileDescriptor.AutoCloseOutputStream(fd)) {
                override fun write(buffer: ByteArray, offset: Int, length: Int) = out.write(buffer, offset, length)
                override fun close() { try { super.close() } finally { request.descriptors.remove(fd) } }
            }
        }
        override fun reader(record: AudioPublicationRecord): PublicationDocumentReader {
            request.stage = 5
            return object : PublicationDocumentReader {
                override fun stamp(): PublicationDocumentStamp {
                    val child = validate(record)!!.second
                    return PublicationDocumentStamp(child.size, child.modified)
                }
                override fun open(): java.io.InputStream {
                    val fd = descriptor(validate(record)!!.first, false)
                    return object : java.io.FilterInputStream(ParcelFileDescriptor.AutoCloseInputStream(fd)) {
                        override fun close() { try { super.close() } finally { request.descriptors.remove(fd) } }
                    }
                }
            }
        }
        override fun find(binding: AudioPublicationBinding): List<String> = children().filter {
            it.name == binding.name && it.mime != DocumentsContract.Document.MIME_TYPE_DIR
        }.map { DocumentsContract.buildDocumentUriUsingTree(tree, it.id).toString() }
        override fun deleteProbe(record: AudioPublicationRecord) {
            require(record.binding.probe && record.owned)
            val uri = validate(record, cleanup = true, missing = true)?.first ?: return
            val payload = AudioPublicationBinding.probeBytes(record.binding.id)
            ParcelFileDescriptor.AutoCloseInputStream(descriptor(uri, false, cleanup = true)).use { input ->
                val buffer = ByteArray(4096); var count = 0; var empty = 0
                while (true) {
                    val length = input.read(buffer)
                    if (length < 0) break
                    if (length == 0) { if (++empty >= 16) throw IOException(); continue }
                    empty = 0
                    require(length <= payload.size - count)
                    for (index in 0 until length) require(buffer[index] == payload[count + index])
                    count += length
                }
            }
            validate(record, cleanup = true)
            if (!DocumentsContract.deleteDocument(resolver, uri)) throw IOException()
            require(validate(record, cleanup = true, missing = true) == null)
        }
    }
    private fun validTree(uri: Uri) = uri.scheme == "content" && !uri.authority.isNullOrEmpty() &&
        uri.query == null && uri.fragment == null && uri.pathSegments.size == 2 &&
        uri.pathSegments[0] == "tree" && uri.pathSegments[1].isNotEmpty() && !uri.pathSegments[1].contains('\u0000')
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true; channel.setMethodCallHandler(null)
        active.get()?.let(::cancel)
        worker.shutdown(); canceller.shutdown()
    }
}
