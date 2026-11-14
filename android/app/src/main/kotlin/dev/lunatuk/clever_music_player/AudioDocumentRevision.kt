package dev.lunatuk.clever_music_player

/** A filesystem-backed provider stamp, not a content hash. */
internal data class AudioDocumentRevision(
    val authority: String,
    val documentId: String,
    val name: String,
    val size: Long,
    val modifiedMs: Long,
) {
    fun message(): Map<String, Any> = mapOf("version" to 1,
        "authority" to authority, "documentId" to documentId, "name" to name,
        "size" to size, "modifiedMs" to modifiedMs)

    companion object {
        fun confirm(before: AudioDocumentRevision?, after: AudioDocumentRevision?,
                    completeRead: Boolean): AudioDocumentRevision? =
            before?.takeIf { completeRead && it == after }

        fun create(authority: String?, id: String?, name: String?, size: Long?,
                   modified: Long?, completeFile: Boolean): AudioDocumentRevision? {
            // Start with the local filesystem provider; other/cloud providers
            // keep the ordinary reader until their revision semantics are known.
            if (authority != "com.android.externalstorage.documents" || !completeFile ||
                id.isNullOrEmpty() || id.length > 4096 || name.isNullOrEmpty() || name.length > 4096 ||
                size == null || size <= 0 || size > 9007199254740991L ||
                modified == null || modified <= 0 || modified > 8640000000000000L) return null
            return AudioDocumentRevision(authority, id, name, size, modified)
        }
    }
}
