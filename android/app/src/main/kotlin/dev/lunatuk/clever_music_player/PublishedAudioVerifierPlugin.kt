package dev.lunatuk.clever_music_player

import android.content.Context
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Read-only verification of a managed document. No account/network access. */
class PublishedAudioVerifierPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val canceller = ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(1), ThreadPoolExecutor.DiscardPolicy())
    private val active = AtomicReference<Request?>(null)
    private var detached = false
    private class MissingDocument : IOException()
    private class Request(val id: Int) {
        val cancelled = AtomicBoolean(false)
        val signal = CancellationSignal()
        val descriptor = AtomicReference<ParcelFileDescriptor?>(null)
    }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger,
            "dev.lunatuk.clever_music_player/publication_verifier")
        channel.setMethodCallHandler(this)
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "verifyPublishedAudio" && call.method != "cancelPublishedAudioVerification") {
            result.notImplemented(); return
        }
        fun integer(key: String): Long? = when (val value = call.argument<Any>(key)) {
            is Int -> value.toLong(); is Long -> value; else -> null
        }
        val id = integer("requestId")
        if (id == null || id !in 1..Int.MAX_VALUE.toLong()) {
            result.error("invalid_request", "Invalid request ID", null); return
        }
        if (call.method == "cancelPublishedAudioVerification") {
            active.get()?.takeIf { it.id == id.toInt() }?.let(::cancel)
            result.success(null); return
        }
        fun uri(key: String): Uri? = (call.argument<Any>(key) as? String)
            ?.takeIf { it.length in 1..8192 }?.let(Uri::parse)
        val tree = uri("tree"); val document = uri("document")
        val name = call.argument<Any>("displayName") as? String
        val digest = call.argument<Any>("digest") as? String
        val size = integer("expectedSize")
        if (detached || tree == null || document == null || !validUris(tree, document) ||
            name == null || !name.matches(Regex("cmp-[0-9a-f]{64}-[0-9a-f]{64}\\.(mp3|m4a|flac)")) ||
            digest == null || !digest.matches(Regex("[0-9a-f]{64}")) ||
            size == null || size !in 1..(8L * 1024 * 1024 * 1024)) {
            result.error("invalid_request", "Invalid publication", null); return
        }
        val request = Request(id.toInt())
        if (!active.compareAndSet(null, request)) {
            result.error("busy", "A publication is already being checked", null); return
        }
        worker.execute {
            val response = verify(request, tree, document, name, size, digest)
            active.compareAndSet(request, null)
            main.post { result.success(response) }
        }
    }
    private fun validUris(tree: Uri, document: Uri): Boolean =
        tree.scheme == "content" && !tree.authority.isNullOrEmpty() &&
        document.scheme == "content" && document.authority == tree.authority &&
        tree.query == null && tree.fragment == null && document.query == null && document.fragment == null &&
        tree.pathSegments.size == 2 && tree.pathSegments[0] == "tree" && tree.pathSegments[1].isNotEmpty() &&
        document.pathSegments.size == 4 && document.pathSegments[0] == "tree" && document.pathSegments[2] == "document" &&
        document.pathSegments[1] == tree.pathSegments[1] && document.pathSegments[3].isNotEmpty() &&
        document.pathSegments[3] != tree.pathSegments[1] &&
        (tree.pathSegments + document.pathSegments).none { it.contains('\u0000') }

    private fun cancel(request: Request) {
        if (!request.cancelled.compareAndSet(false, true)) return
        canceller.execute {
            runCatching { request.signal.cancel() }
            runCatching { request.descriptor.getAndSet(null)?.close() }
        }
    }
    private fun verify(request: Request, tree: Uri, document: Uri, name: String,
        size: Long, digest: String): Map<String, Any> {
        fun response(status: String) = mapOf<String, Any>("requestId" to request.id, "status" to status)
        try {
            val reader = object : PublicationDocumentReader {
                override fun stamp(): PublicationDocumentStamp = metadata(tree, document, name, request.signal)
                override fun open(): java.io.InputStream {
                    val fd = context.contentResolver.openFileDescriptor(document, "r", request.signal) ?: throw IOException()
                    request.descriptor.set(fd)
                    return object : java.io.FilterInputStream(ParcelFileDescriptor.AutoCloseInputStream(fd)) {
                        override fun close() { try { super.close() } finally { request.descriptor.compareAndSet(fd, null) } }
                    }
                }
            }
            val proof = PublishedAudioVerification.verify(reader, size, digest) { request.cancelled.get() }
            return response("fingerprinted") + mapOf("sizeBytes" to proof.sizeBytes, "digest" to proof.digest)
        } catch (_: ContentChangedException) {
            return response(if (request.cancelled.get()) "cancelled" else "changed")
        } catch (_: SecurityException) {
            return response(if (request.cancelled.get()) "cancelled" else "accessDenied")
        } catch (_: MissingDocument) {
            return response(if (request.cancelled.get()) "cancelled" else "missing")
        } catch (_: Exception) {
            return response(if (request.cancelled.get()) "cancelled" else "unreadable")
        } finally {
            runCatching { request.descriptor.getAndSet(null)?.close() }
        }
    }
    private fun metadata(tree: Uri, document: Uri, name: String, signal: CancellationSignal): PublicationDocumentStamp {
        val resolver = context.contentResolver
        if (!resolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission && it.isWritePermission }) throw SecurityException()
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val root = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
        resolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null, signal).use { cursor ->
            if (cursor == null || !cursor.moveToFirst() || cursor.getString(0) != DocumentsContract.Document.MIME_TYPE_DIR) throw IOException()
        }
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, rootId)
        val id = DocumentsContract.getDocumentId(document)
        resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED),
            null, null, null, signal).use { cursor ->
            if (cursor == null) throw IOException()
            var count = 0
            while (cursor.moveToNext()) {
                signal.throwIfCanceled()
                if (++count > 10000) throw IOException()
                if (cursor.getString(0) != id) continue
                if (cursor.getString(1) != name || cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) throw ContentChangedException()
                fun number(index: Int) = if (cursor.isNull(index)) null else cursor.getLong(index).takeIf { it >= 0 }
                return PublicationDocumentStamp(number(3), number(4))
            }
        }
        throw MissingDocument()
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true
        channel.setMethodCallHandler(null)
        active.get()?.let(::cancel)
        worker.shutdown(); canceller.shutdown()
    }
}
