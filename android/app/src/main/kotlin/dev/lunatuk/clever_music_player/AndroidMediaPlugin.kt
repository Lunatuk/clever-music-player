package dev.lunatuk.clever_music_player

import android.content.Context
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import androidx.core.net.toUri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

internal object AndroidMediaNative {
    val loaded: Boolean by lazy {
        try { System.loadLibrary("cmp_media"); true } catch (_: LinkageError) { false }
    }
    external fun begin(): Boolean
    external fun cancel()
    external fun end()
    external fun inspectDescriptor(fd: Int, declaredLength: Long, compare: Boolean): ByteArray
    external fun run(op: Int, source: ByteArray?, output: ByteArray?, cover: ByteArray?,
        coverFormat: Int, mode: Int, limit: Long, tags: Array<ByteArray?>): ByteArray
}

/** App-private processing and read-only analysis of granted local documents. */
class AndroidMediaPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private data class Operation(val id: Int, val cancellation: CancellationSignal = CancellationSignal())
    private val active = AtomicReference<Operation?>(null)
    private var detached = false
    private val keys = listOf("title","artist","album","album_artist","genre","track","disc","date","comment")
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger,"dev.lunatuk.clever_music_player/media_backend")
        channel.setMethodCallHandler(this)
    }
    override fun onMethodCall(call: MethodCall,result: MethodChannel.Result) {
        if (call.method !in setOf("runMediaOperation","cancelMediaOperation")) { result.notImplemented(); return }
        val number = call.argument<Any>("requestId")
        val value = when (number) { is Int -> number.toLong(); is Long -> number; else -> null }
        if (value == null || value !in 1..Int.MAX_VALUE.toLong()) { result.error("invalid_request","Invalid media request",null); return }
        val id = value.toInt()
        if (call.method == "cancelMediaOperation") {
            active.get()?.takeIf { it.id == id }?.let(::cancel)
            result.success(null); return
        }
        if (detached) { result.error("closed","Media backend closed",null); return }
        fun reply(status: String) = result.success(mapOf("requestId" to id,"status" to status))
        if (!AndroidMediaNative.loaded) { reply("backendUnavailable"); return }
        val op: Int; val source: ByteArray?; val output: ByteArray?; val cover: ByteArray?
        val document: Uri?
        val coverFormat: Int; val mode: Int; val limit: Long; val tags: Array<ByteArray?>
        try {
            op = call.argument<Int>("op") ?: error("op"); require(op in 0..5)
            document = call.argument<String>("document")?.let {
                require((op == 1 || op == 4) && it.length <= 16384 && call.argument<String>("source") == null)
                it.toUri().also { uri ->
                    require(uri.scheme == "content" && uri.authority == "com.android.externalstorage.documents" &&
                        uri.query == null && uri.fragment == null && DocumentsContract.isDocumentUri(context, uri))
                }
            }
            source = if (op == 0 || document != null) null else path(call.argument<String>("source"),false)
            output = if (op == 5) path(call.argument<String>("output"),true) else null
            cover = call.argument<String>("cover")?.let { require(op == 5); path(it,false) }
            coverFormat = call.argument<Int>("coverFormat") ?: 0
            require((cover == null && coverFormat == 0) || (cover != null && coverFormat in 1..2))
            mode = call.argument<Int>("mode") ?: 0; require(mode in 0..2)
            require(document == null || op == 1 || mode == 1)
            limit = when (val value = call.argument<Any>("maxOutputBytes")) { is Int -> value.toLong(); is Long -> value; null -> 8L*1024*1024*1024; else -> error("limit") }
            require(limit in 1..(8L*1024*1024*1024))
            val values = call.argument<Map<String,String>>("tags") ?: emptyMap()
            require(values.size <= keys.size && values.keys.all { it in keys } && values.values.sumOf { it.length } <= 8192)
            require(values.values.all { it.isNotBlank() && it.length <= 4096 && !it.contains('\u0000') })
            tags = keys.map { values[it]?.toByteArray(Charsets.UTF_8) }.toTypedArray()
        } catch (_: Exception) { reply("unreadable"); return }
        val operation = Operation(id)
        if (!active.compareAndSet(null,operation)) { reply("busy"); return }
        if (!AndroidMediaNative.begin()) { active.set(null); reply("busy"); return }
        worker.execute {
            val response = try {
                val inspected = document?.let { inspectDocument(it, operation.cancellation, compare = op == 4) }
                val bytes = inspected?.first ?: AndroidMediaNative.run(op,source,output,cover,coverFormat,mode,limit,tags)
                require(bytes.size in 1..131072)
                val text = Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                val json = JSONObject(text)
                require(json.getString("status") in setOf("ok","cancelled","timedOut","unreadable","invalidAudio","invalidCover","coverMissing","quotaExceeded"))
                objectValue(json) + mapOf("requestId" to id, "sourceComments" to inspected?.second)
            } catch (_: Exception) { mapOf("requestId" to id,"status" to "unreadable") }
            finally { active.set(null); AndroidMediaNative.end() }
            main.post { result.success(response) }
        }
    }
    private fun cancel(operation: Operation) {
        AndroidMediaNative.cancel()
        operation.cancellation.cancel()
    }

    private fun inspectDocument(uri: Uri, cancellation: CancellationSignal, compare: Boolean): Pair<ByteArray, List<String>?> {
        val resolver = context.contentResolver
        require(resolver.persistedUriPermissions.any {
            it.isReadPermission && (it.uri == uri ||
                (it.uri.authority == uri.authority && DocumentsContract.isTreeUri(it.uri) &&
                    DocumentsContract.isTreeUri(uri) &&
                    DocumentsContract.getTreeDocumentId(it.uri) == DocumentsContract.getTreeDocumentId(uri)))
        })
        return resolver.openAssetFileDescriptor(uri, "r", cancellation).use { asset ->
            require(asset != null && asset.startOffset == 0L)
            cancellation.throwIfCanceled()
            val length = asset.declaredLength
            val result = AndroidMediaNative.inspectDescriptor(asset.parcelFileDescriptor.fd, length, compare)
            cancellation.throwIfCanceled()
            if (compare) return@use result to null
            val comments = android.os.ParcelFileDescriptor.dup(asset.fileDescriptor).let { duplicate ->
                android.os.ParcelFileDescriptor.AutoCloseInputStream(duplicate).use {
                    AudioSourceComments.read(it.channel, 0, length)
                }
            }
            result to comments
        }
    }
    private fun path(raw: String?, output: Boolean): ByteArray {
        return privateMediaPath(context.filesDir.canonicalFile,raw,output)
    }
    private fun objectValue(json: JSONObject): Map<String,Any?> = json.keys().asSequence().associateWith { key ->
        when (val value = json.get(key)) {
            JSONObject.NULL -> null
            is JSONObject -> objectValue(value)
            is JSONArray -> error("unexpected_array")
            else -> value
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true; channel.setMethodCallHandler(null)
        active.get()?.let(::cancel)
        worker.shutdown()
    }
}
