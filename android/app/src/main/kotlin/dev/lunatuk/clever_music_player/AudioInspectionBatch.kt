package dev.lunatuk.clever_music_player

import java.io.File

internal data class AudioInspectionRequest(val source: String, val hasArtwork: Boolean,
    val artworkPath: String?, val artworkHash: String?)

/** Limits are checked between calls: a provider already in flight may take longer. */
internal object AudioInspectionBatch {
    const val MAX_ITEMS = 8
    const val BUDGET_NS = 200000000L

    fun run(items: List<AudioInspectionRequest>, cancelled: () -> Boolean,
            inspect: (AudioInspectionRequest) -> Map<String, Any?>,
            clock: () -> Long = System::nanoTime): Map<String, Any?> {
        require(items.isNotEmpty() && items.size <= MAX_ITEMS &&
            items.map { it.source }.toSet().size == items.size)
        val started = clock()
        val completed = mutableListOf<Pair<Map<String, Any?>, Long>>()
        for (item in items) {
            if (cancelled()) break
            val frame = try { inspect(item) } catch (_: Exception) {
                mapOf("failed" to true, "artwork" to 0)
            }
            if (cancelled()) break
            completed.add((frame + ("source" to item.source)) to clock())
            if (clock() - started >= BUDGET_NS) break
        }
        val ended = clock()
        return mapOf("version" to 1, "consumed" to completed.size,
            "cancelled" to cancelled(), "results" to completed.map { (frame, checkedAt) ->
                frame + ("ageUs" to ((ended - checkedAt).coerceAtLeast(0) / 1000))
            })
    }
}

/** Only positively attests content-addressed files in the app's embedded cache.
 * Unsupported paths retain the Dart fallback; this class never writes files. */
internal class AudioArtworkProbe(private val root: File) {
    fun check(request: AudioInspectionRequest): Int {
        if (!request.hasArtwork) return 3 // reliable absence in cached metadata
        val path = request.artworkPath ?: return 0
        val hash = request.artworkHash ?: return 0
        if (path.length > 8192 || !hash.matches(Regex("[0-9a-f]{64}"))) return 0
        return try {
            val original = File(path)
            val file = original.canonicalFile
            if (!original.isAbsolute || file.parentFile != root.canonicalFile ||
                !file.name.matches(Regex("${hash}\\.(jpg|jpeg|png|webp|gif|tif|tiff|bmp|bin)"))) 0
            else if (file.isFile && file.length() > 0) 1 else 2
        } catch (_: Exception) { 0 }
    }
}
