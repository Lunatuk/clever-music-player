package dev.lunatuk.clever_music_player

import java.io.InputStream

internal data class PublicationDocumentStamp(val size: Long?, val modified: Long?)
internal interface PublicationDocumentReader {
    /** Must check current grants, direct parent and exact display name. */
    fun stamp(): PublicationDocumentStamp
    fun open(): InputStream
}

/** Readback is point-in-time evidence, not a permanent provider write seal. */
internal object PublishedAudioVerification {
    fun verify(reader: PublicationDocumentReader, size: Long, digest: String,
        cancelled: () -> Boolean): ContentFingerprint {
        require(size in 1..(8L * 1024 * 1024 * 1024))
        require(digest.matches(Regex("[0-9a-f]{64}")))
        if (cancelled()) throw java.util.concurrent.CancellationException()
        val before = reader.stamp()
        if (before.size != null && before.size != size) throw ContentChangedException()
        val actual = reader.open().use { StreamingContentFingerprint.read(it, size, cancelled) }
        if (actual.digest != digest) throw ContentChangedException()
        val after = reader.stamp()
        if (cancelled()) throw java.util.concurrent.CancellationException()
        if ((after.size != null && after.size != size) ||
            (before.modified != null && after.modified != null && before.modified != after.modified)) {
            throw ContentChangedException()
        }
        return actual
    }
}
