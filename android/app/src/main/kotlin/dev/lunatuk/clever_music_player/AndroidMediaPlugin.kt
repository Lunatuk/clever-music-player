package dev.lunatuk.clever_music_player

import android.content.Context
import android.os.Handler
import android.os.Looper
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
    external fun run(op: Int, source: ByteArray?, output: ByteArray?, cover: ByteArray?,
        coverFormat: Int, mode: Int, limit: Long, tags: Array<ByteArray?>): ByteArray
}

/** Lazy, app-private file processing; no source URI, network or subprocesses. */
class AndroidMediaPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val active = AtomicReference<Int?>(null)
    private var detached = false
    private val keys = listOf("title","artist","album","album_artist","genre","track","disc","date")
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
            if (active.get() == id) AndroidMediaNative.cancel()
            result.success(null); return
        }
        if (detached) { result.error("closed","Media backend closed",null); return }
        fun reply(status: String) = result.success(mapOf("requestId" to id,"status" to status))
        if (!AndroidMediaNative.loaded) { reply("backendUnavailable"); return }
        val op: Int; val source: ByteArray?; val output: ByteArray?; val cover: ByteArray?
        val coverFormat: Int; val mode: Int; val limit: Long; val tags: Array<ByteArray?>
        try {
            op = call.argument<Int>("op") ?: error("op"); require(op in 0..5)
            source = if (op == 0) null else path(call.argument<String>("source"),false)
            output = if (op == 5) path(call.argument<String>("output"),true) else null
            cover = call.argument<String>("cover")?.let { require(op == 5); path(it,false) }
            coverFormat = call.argument<Int>("coverFormat") ?: 0
            require((cover == null && coverFormat == 0) || (cover != null && coverFormat in 1..2))
            mode = call.argument<Int>("mode") ?: 0; require(mode in 0..2)
            limit = when (val value = call.argument<Any>("maxOutputBytes")) { is Int -> value.toLong(); is Long -> value; null -> 8L*1024*1024*1024; else -> error("limit") }
            require(limit in 1..(8L*1024*1024*1024))
            val values = call.argument<Map<String,String>>("tags") ?: emptyMap()
            require(values.size <= 8 && values.keys.all { it in keys } && values.values.sumOf { it.length } <= 8192)
            require(values.values.all { it.isNotBlank() && it.length <= 4096 && !it.contains('\u0000') })
            tags = keys.map { values[it]?.toByteArray(Charsets.UTF_8) }.toTypedArray()
        } catch (_: Exception) { reply("unreadable"); return }
        if (!active.compareAndSet(null,id)) { reply("busy"); return }
        if (!AndroidMediaNative.begin()) { active.set(null); reply("busy"); return }
        worker.execute {
            val response = try {
                val bytes = AndroidMediaNative.run(op,source,output,cover,coverFormat,mode,limit,tags)
                require(bytes.size in 1..131072)
                val text = Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                val json = JSONObject(text)
                require(json.getString("status") in setOf("ok","cancelled","timedOut","unreadable","invalidAudio","invalidCover","coverMissing","quotaExceeded"))
                objectValue(json) + mapOf("requestId" to id)
            } catch (_: Exception) { mapOf("requestId" to id,"status" to "unreadable") }
            finally { active.set(null); AndroidMediaNative.end() }
            main.post { result.success(response) }
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
        if (active.get() != null) AndroidMediaNative.cancel()
        worker.shutdown()
    }
}
