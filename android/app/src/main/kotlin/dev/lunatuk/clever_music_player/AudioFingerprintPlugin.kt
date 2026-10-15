package dev.lunatuk.clever_music_player

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.OperationCanceledException
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** One bounded SAF read, independent of the document browser/metadata worker. */
class AudioFingerprintPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
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
        val descriptor = AtomicReference<AssetFileDescriptor?>(null)
    }
    private data class Metadata(val size: Long?, val modified: Long?)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger,
            "dev.lunatuk.clever_music_player/audio_fingerprint")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "fingerprintAudio" && call.method != "cancelAudioFingerprint") {
            result.notImplemented()
            return
        }
        fun integer(key: String): Long? = when (val value = call.argument<Any>(key)) {
            is Int -> value.toLong()
            is Long -> value
            else -> null
        }
        val id = integer("requestId")
        if (id == null || id !in 1..Int.MAX_VALUE.toLong()) {
            result.error("invalid_request", "Invalid request ID", null)
            return
        }
        if (call.method == "cancelAudioFingerprint") {
            active.get()?.takeIf { it.id == id.toInt() }?.let(::cancel)
            result.success(null)
            return
        }
        val size = integer("expectedSize")
        val rawUri = call.argument<Any>("uri") as? String
        val uri = rawUri?.let(Uri::parse)
        if (detached || size == null || size <= 0 || uri == null ||
            uri.scheme != "content" || uri.authority.isNullOrEmpty() || uri.path.isNullOrEmpty()) {
            result.error("invalid_request", "Invalid audio source", null)
            return
        }
        val request = Request(id.toInt())
        if (!active.compareAndSet(null, request)) {
            result.error("busy", "A document is already being checked", null)
            return
        }
        worker.execute {
            val response = read(request, uri, size)
            active.compareAndSet(request, null)
            main.post { result.success(response) }
        }
    }

    private fun cancel(request: Request) {
        if (!request.cancelled.compareAndSet(false, true)) return
        // CancellationSignal/provider close may block too; never run on the UI
        // thread or behind the read being cancelled. No repeated queued tasks.
        canceller.execute {
            runCatching { request.signal.cancel() }
            runCatching { request.descriptor.get()?.close() }
        }
    }

    private fun read(request: Request, uri: Uri, expectedSize: Long): Map<String, Any> {
        fun response(status: String) = mapOf<String, Any>("requestId" to request.id, "status" to status)
        try {
            if (request.cancelled.get()) return response("cancelled")
            // Current imports use persisted SAF grants, including tree grants.
            // No grant means accessDenied, never infer missing from that case.
            if (!hasPersistentRead(uri)) return response("accessDenied")
            val before = metadata(uri, request.signal)
            val opened = context.contentResolver.openAssetFileDescriptor(uri, "r", request.signal)
                ?: return response("unreadable")
            request.descriptor.set(opened)
            val fingerprint = opened.use { descriptor ->
                if (request.cancelled.get()) throw CancellationException()
                if ((before.size != null && before.size != expectedSize) ||
                    (descriptor.declaredLength >= 0 && descriptor.declaredLength != expectedSize)) {
                    throw ContentChangedException()
                }
                descriptor.createInputStream().use { input ->
                    StreamingContentFingerprint.read(input, expectedSize) { request.cancelled.get() }
                }
            }
            request.descriptor.set(null)
            val after = metadata(uri, request.signal)
            if (request.cancelled.get()) return response("cancelled")
            if ((after.size != null && after.size != expectedSize) ||
                (before.modified != null && after.modified != null && before.modified != after.modified)) {
                return response("changed")
            }
            return response("fingerprinted") + mapOf("sizeBytes" to fingerprint.sizeBytes, "digest" to fingerprint.digest)
        } catch (_: ContentChangedException) {
            return response(if (request.cancelled.get()) "cancelled" else "changed")
        } catch (_: CancellationException) {
            return response("cancelled")
        } catch (_: OperationCanceledException) {
            return response(if (request.cancelled.get()) "cancelled" else "unreadable")
        } catch (_: SecurityException) {
            return response(if (request.cancelled.get()) "cancelled" else "accessDenied")
        } catch (_: FileNotFoundException) {
            // Revocation may race the initial grant check.
            val status = if (request.cancelled.get()) "cancelled"
                else if (!runCatching { hasPersistentRead(uri) }.getOrDefault(false)) "accessDenied" else "missing"
            return response(status)
        } catch (_: Exception) {
            return response(if (request.cancelled.get()) "cancelled" else "unreadable")
        } finally {
            runCatching { request.descriptor.getAndSet(null)?.close() }
        }
    }

    private fun hasPersistentRead(uri: Uri): Boolean = context.contentResolver.persistedUriPermissions.any {
        it.isReadPermission && (it.uri == uri ||
            (it.uri.authority == uri.authority && DocumentsContract.isTreeUri(it.uri) &&
                DocumentsContract.isTreeUri(uri) &&
                DocumentsContract.getTreeDocumentId(it.uri) == DocumentsContract.getTreeDocumentId(uri)))
    }

    private fun metadata(uri: Uri, signal: CancellationSignal): Metadata {
        fun query(includeModified: Boolean): Metadata {
            val columns = if (includeModified) arrayOf(OpenableColumns.SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                else arrayOf(OpenableColumns.SIZE)
            context.contentResolver.query(uri, columns, null, null, null, signal).use { cursor ->
                if (cursor == null || !cursor.moveToFirst()) return Metadata(null, null)
                fun value(column: String): Long? {
                    val index = cursor.getColumnIndex(column)
                    if (index < 0 || cursor.isNull(index)) return null
                    return cursor.getLong(index).takeIf { it >= 0 }
                }
                return Metadata(value(OpenableColumns.SIZE), value(DocumentsContract.Document.COLUMN_LAST_MODIFIED))
            }
        }
        return try { query(true) } catch (_: IllegalArgumentException) { query(false) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true
        channel.setMethodCallHandler(null)
        active.get()?.let(::cancel)
        worker.shutdown()
        canceller.shutdown()
    }
}
