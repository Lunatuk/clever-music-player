package dev.lunatuk.clever_music_player

import android.content.Context
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.util.AtomicFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Explicit destination probe only. No music publication is exposed yet. */
class DownloadPublicationPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val canceller = ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(1), ThreadPoolExecutor.DiscardPolicy())
    private val active = AtomicReference<Request?>(null)
    private var detached = false

    private class Request(val id: Int) {
        val cancelled = AtomicBoolean(false)
        val signal = CancellationSignal()
        val descriptor = AtomicReference<ParcelFileDescriptor?>(null)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger,
            "dev.lunatuk.clever_music_player/download_publication")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "checkDownloadDestination" && call.method != "cancelDownloadDestinationCheck") {
            result.notImplemented(); return
        }
        val number = call.argument<Any>("requestId")
        val id = when (number) { is Int -> number.toLong(); is Long -> number; else -> null }
        if (id == null || id !in 1..Int.MAX_VALUE.toLong()) {
            result.error("invalid_request", "Invalid request ID", null); return
        }
        if (call.method == "cancelDownloadDestinationCheck") {
            active.get()?.takeIf { it.id == id.toInt() }?.let(::cancel)
            result.success(null); return
        }
        val raw = call.argument<Any>("uri") as? String
        val tree = raw?.takeIf { it.length <= 8192 }?.let(Uri::parse)
        if (detached || tree == null || !validTree(tree)) {
            result.error("invalid_request", "Invalid destination", null); return
        }
        val request = Request(id.toInt())
        if (!active.compareAndSet(null, request)) {
            result.error("busy", "A destination is already being checked", null); return
        }
        worker.execute {
            val response = check(request, tree)
            active.compareAndSet(request, null)
            main.post {
                result.success(mapOf("requestId" to request.id, "status" to response.status,
                    "stage" to response.stage, "verifiedBytes" to response.verifiedBytes,
                    "recovered" to response.recovered, "retained" to response.retained))
            }
        }
    }

    private fun cancel(request: Request) {
        if (!request.cancelled.compareAndSet(false, true)) return
        canceller.execute {
            runCatching { request.signal.cancel() }
            runCatching { request.descriptor.getAndSet(null)?.close() }
        }
    }

    private fun check(request: Request, tree: Uri): DestinationCheckResult {
        try {
            if (request.cancelled.get()) return DestinationCheckResult("cancelled", 0)
            val directory = File(context.filesDir, "download-destination-probes-v1")
            if (!directory.isDirectory && !directory.mkdir()) throw IOException()
            RandomAccessFile(File(directory, "owner.lock"), "rw").use { owner ->
                val lock = try { owner.channel.tryLock() } catch (_: java.nio.channels.OverlappingFileLockException) { null }
                    ?: return DestinationCheckResult("busy", 0)
                lock.use {
                    val documents = SafProbeDocuments(context, tree, request)
                    documents.checkRoot()
                    return DownloadDestinationCheck(AtomicProbeJournal(directory), documents)
                        .run(tree.toString()) { request.cancelled.get() }
                }
            }
        } catch (_: SecurityException) {
            return DestinationCheckResult("accessDenied", 0)
        } catch (_: UnsupportedOperationException) {
            return DestinationCheckResult("unsupported", 0)
        } catch (_: Exception) {
            return DestinationCheckResult(if (request.cancelled.get()) "cancelled" else "io", 0)
        } finally {
            runCatching { request.descriptor.getAndSet(null)?.close() }
        }
    }

    private class AtomicProbeJournal(private val directory: File) : DestinationProbeJournal {
        override fun records(): List<DestinationProbeRecord> {
            val files = directory.listFiles() ?: throw IOException()
            // AtomicFile's base/bak/new entries share a logical operation ID.
            val ids = files.filter { it.name != "owner.lock" }.map {
                val name = it.name.removeSuffix(".bak").removeSuffix(".new")
                require(name.matches(Regex("[0-9a-f]{32}\\.probe")))
                name.removeSuffix(".probe")
            }.toSet()
            require(ids.size <= 64)
            return ids.map { id ->
                AtomicFile(File(directory, "$id.probe")).openRead().use { input ->
                    val bytes = input.readBytesBounded()
                    DestinationProbeCodec.decode(bytes).also { require(it.id == id) }
                }
            }
        }
        private fun java.io.InputStream.readBytesBounded(): ByteArray {
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            while (true) {
                val count = read(buffer)
                if (count < 0) return out.toByteArray()
                if (count == 0 || out.size() + count > 32768) throw IOException()
                out.write(buffer, 0, count)
            }
        }
        override fun save(record: DestinationProbeRecord) {
            val bytes = DestinationProbeCodec.encode(record)
            val file = AtomicFile(File(directory, "${record.id}.probe"))
            val stream = file.startWrite()
            try { stream.write(bytes); stream.fd.sync(); file.finishWrite(stream) }
            catch (error: Exception) { file.failWrite(stream); throw error }
            // AtomicFile.finishWrite logs rather than propagates some failures.
            file.openRead().use { require(DestinationProbeCodec.decode(it.readBytesBounded()) == record) }
        }
        override fun remove(record: DestinationProbeRecord) {
            val base = File(directory, "${record.id}.probe")
            AtomicFile(base).delete()
            require(listOf(base, File(base.path + ".bak"), File(base.path + ".new")).none { it.exists() })
        }
    }

    private class SafProbeDocuments(private val context: Context, private val tree: Uri,
        private val request: Request) : DestinationProbeDocuments {
        private val resolver get() = context.contentResolver
        private val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        private data class Child(val id: String, val name: String, val mime: String)
        fun checkRoot(cleanup: Boolean = false) {
            if (!resolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission && it.isWritePermission })
                throw SecurityException()
            resolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_FLAGS), null, null, null,
                if (cleanup) null else request.signal).use { cursor ->
                if (cursor == null || !cursor.moveToFirst()) throw IOException()
                if (cursor.getString(0) != DocumentsContract.Document.MIME_TYPE_DIR ||
                    cursor.getInt(1) and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE == 0)
                    throw UnsupportedOperationException()
            }
        }
        private fun children(cleanup: Boolean = false): List<Child> {
            checkRoot(cleanup)
            val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val result = ArrayList<Child>()
            resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE),
                null, null, null, if (cleanup) null else request.signal).use { cursor ->
                if (cursor == null) throw IOException()
                while (cursor.moveToNext()) {
                    if (result.size >= 10000) throw UnsupportedOperationException()
                    result.add(Child(cursor.getString(0), cursor.getString(1), cursor.getString(2)))
                }
            }
            return result
        }
        private fun validated(record: DestinationProbeRecord, allowMissing: Boolean = false,
            cleanup: Boolean = false): Uri? {
            require(record.tree == tree.toString())
            val uri = record.uri?.let(Uri::parse) ?: throw IOException()
            require(uri.scheme == "content" && uri.authority == tree.authority && uri.query == null && uri.fragment == null &&
                DocumentsContract.isTreeUri(uri) && DocumentsContract.getTreeDocumentId(uri) == DocumentsContract.getTreeDocumentId(tree))
            val id = DocumentsContract.getDocumentId(uri)
            require(id != DocumentsContract.getTreeDocumentId(tree))
            val matches = children(cleanup).filter { it.id == id }
            if (matches.isEmpty() && allowMissing) return null
            require(matches.size == 1 && matches[0].name == record.name && matches[0].mime != DocumentsContract.Document.MIME_TYPE_DIR)
            return DocumentsContract.buildDocumentUriUsingTree(tree, id)
        }
        override fun create(record: DestinationProbeRecord): String {
            val before = children()
            require(before.none { it.name == record.name })
            if (request.cancelled.get()) throw CancellationException()
            val created = DocumentsContract.createDocument(resolver, root, "application/octet-stream", record.name) ?: throw IOException()
            // Reject provider redirection/renaming before opening any descriptor.
            val candidate = record.copy(uri = created.toString())
            val checked = validated(candidate) ?: throw IOException()
            require(before.none { it.id == DocumentsContract.getDocumentId(checked) })
            return checked.toString()
        }
        override fun exists(record: DestinationProbeRecord): Boolean = validated(record, true, cleanup = true) != null
        override fun output(record: DestinationProbeRecord): java.io.OutputStream {
            val uri = validated(record) ?: throw IOException()
            if (request.cancelled.get()) throw CancellationException()
            val fd = resolver.openFileDescriptor(uri, "w", request.signal) ?: throw IOException()
            request.descriptor.set(fd)
            if (request.cancelled.get()) { request.descriptor.compareAndSet(fd, null); fd.close(); throw CancellationException() }
            return object : java.io.FilterOutputStream(ParcelFileDescriptor.AutoCloseOutputStream(fd)) {
                override fun write(buffer: ByteArray, offset: Int, length: Int) = out.write(buffer, offset, length)
                override fun close() { try { super.close() } finally { request.descriptor.compareAndSet(fd, null) } }
            }
        }
        override fun input(record: DestinationProbeRecord, cleanup: Boolean): java.io.InputStream {
            val uri = validated(record, cleanup = cleanup) ?: throw IOException()
            val fd = resolver.openFileDescriptor(uri, "r", if (cleanup) null else request.signal) ?: throw IOException()
            if (!cleanup) request.descriptor.set(fd)
            return object : java.io.FilterInputStream(ParcelFileDescriptor.AutoCloseInputStream(fd)) {
                override fun close() { try { super.close() } finally { request.descriptor.compareAndSet(fd, null) } }
            }
        }
        override fun delete(record: DestinationProbeRecord) {
            val uri = validated(record, true, cleanup = true) ?: return
            if (!DocumentsContract.deleteDocument(resolver, uri)) throw IOException()
            if (validated(record, true, cleanup = true) != null) throw IOException()
        }
    }

    private fun validTree(uri: Uri): Boolean = uri.scheme == "content" && !uri.authority.isNullOrEmpty() &&
        uri.query == null && uri.fragment == null && DocumentsContract.isTreeUri(uri) && uri.pathSegments.size == 2

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true
        channel.setMethodCallHandler(null)
        active.get()?.let(::cancel)
        worker.shutdown()
        canceller.shutdown()
    }
}
