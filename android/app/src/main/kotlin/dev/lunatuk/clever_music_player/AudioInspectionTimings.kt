package dev.lunatuk.clever_music_player

/** Revision time includes the visibility subset; no addresses enter this map. */
internal class AudioInspectionTimings {
    var permissionNs = 0L
    var revisionNs = 0L
    var visibilityNs = 0L
    var descriptorNs = 0L
    var artworkNs = 0L

    fun message(totalNs: Long): Map<String, Any> = mapOf("version" to 1,
        "totalUs" to totalNs / 1000, "permissionUs" to permissionNs / 1000,
        "revisionUs" to revisionNs / 1000, "visibilityUs" to visibilityNs / 1000,
        "descriptorUs" to descriptorNs / 1000, "artworkUs" to artworkNs / 1000)
}
