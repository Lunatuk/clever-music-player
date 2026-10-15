package dev.lunatuk.clever_music_player

import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.CancellationException

internal class ContentChangedException : IOException()

internal data class ContentFingerprint(val sizeBytes: Long, val digest: String)

/** Caller owns the stream. Bounded memory even for a broken/unbounded provider. */
internal object StreamingContentFingerprint {
    fun read(input: InputStream, expectedSize: Long, cancelled: () -> Boolean): ContentFingerprint {
        require(expectedSize > 0)
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        var count = 0L
        var emptyReads = 0
        fun checkCancellation() {
            if (cancelled()) throw CancellationException()
        }
        while (true) {
            checkCancellation()
            val length = input.read(buffer)
            checkCancellation()
            if (length < 0) break
            if (length == 0) {
                if (++emptyReads >= 16) throw IOException("No read progress")
                continue
            }
            emptyReads = 0
            if (length.toLong() > expectedSize - count) throw ContentChangedException()
            count += length
            digest.update(buffer, 0, length)
        }
        checkCancellation()
        if (count != expectedSize) throw ContentChangedException()
        val hex = "0123456789abcdef"
        val hash = buildString(64) {
            for (byte in digest.digest()) {
                append(hex[(byte.toInt() and 0xff) ushr 4])
                append(hex[byte.toInt() and 0x0f])
            }
        }
        return ContentFingerprint(count, hash)
    }
}
