package dev.lunatuk.clever_music_player

import java.util.ArrayDeque

data class TreeDocument(val id: String, val mime: String?, val name: String?, val sizeBytes: Long? = null)
interface TreeDirectoryCursor : AutoCloseable {
    fun next(): TreeDocument?
}
data class TreeAudioPage(val ids: List<String>, val visited: Int, val done: Boolean)

/** Bounded, incremental traversal. Does not retain metadata or audio bytes. */
class DocumentTreeWalker(
    rootId: String,
    private val openDirectory: (String) -> TreeDirectoryCursor,
    private val cancelled: () -> Boolean = { false },
    private val maxNodes: Int = 100_000,
    private val pageSize: Int = 64,
    private val pageWork: Int = 256,
    private val includeAudio: (TreeDocument) -> Boolean = { true }
) : AutoCloseable {
    private val pending = ArrayDeque<String>().apply { add(rootId) }
    private val directories = hashSetOf(rootId)
    private val audio = hashSetOf<String>()
    private var cursor: TreeDirectoryCursor? = null
    private var visited = 0
    private var closed = false

    init { require(maxNodes > 0 && pageSize > 0 && pageWork > 0) }

    fun nextPage(): TreeAudioPage {
        check(!closed)
        val found = ArrayList<String>()
        var work = 0
        try {
            while (found.size < pageSize && work < pageWork) {
                check(!cancelled()) { "cancelled" }
                if (cursor == null) {
                    if (pending.isEmpty()) break
                    cursor = openDirectory(pending.removeFirst())
                    work++
                    if (++visited > maxNodes) error("tree_limit")
                    if (work >= pageWork) break
                }
                val entry = cursor!!.next()
                if (entry == null) {
                    val finished = cursor
                    cursor = null
                    finished!!.close()
                    continue
                }
                work++
                if (++visited > maxNodes) error("tree_limit")
                if (entry.mime == "vnd.android.document/directory") {
                    if (directories.add(entry.id)) pending.add(entry.id)
                } else if (isAudio(entry) && includeAudio(entry) && audio.add(entry.id)) {
                    found.add(entry.id)
                }
            }
            return TreeAudioPage(found, visited, pending.isEmpty() && cursor == null)
        } catch (error: Exception) {
            try { close() } catch (_: Exception) { /* preserve original error */ }
            throw error
        }
    }

    private fun isAudio(entry: TreeDocument): Boolean = entry.sizeBytes != 0L && (
        entry.mime?.startsWith("audio/") == true ||
            entry.name?.substringAfterLast('.', "")?.lowercase(java.util.Locale.ROOT) in
                extensions)

    private companion object {
        val extensions = setOf("mp3", "flac", "m4a", "aac", "ogg", "wav")
    }

    override fun close() {
        if (closed) return
        closed = true
        pending.clear()
        directories.clear()
        audio.clear()
        val current = cursor
        cursor = null
        current?.close()
    }
}
