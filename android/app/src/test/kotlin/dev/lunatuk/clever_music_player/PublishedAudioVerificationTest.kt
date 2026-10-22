package dev.lunatuk.clever_music_player

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.CancellationException

class PublishedAudioVerificationTest {
    private val hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private class Reader : PublicationDocumentReader {
        var before = PublicationDocumentStamp(3, 1)
        var after = before
        var stamps = 0
        var opened = false
        var closed = false
        var payload = "abc".toByteArray()
        var failClose = false
        var secondFailure: Exception? = null
        override fun stamp(): PublicationDocumentStamp {
            if (++stamps == 1) return before
            assertTrue(closed)
            secondFailure?.let { throw it }
            return after
        }
        override fun open(): InputStream {
            opened = true
            return object : ByteArrayInputStream(payload) {
                override fun close() { closed = true; if (failClose) throw IOException() }
            }
        }
    }
    @Test fun closesFullReadBeforeCheckingParentAndMetadataAgain() {
        val reader = Reader()
        assertEquals(ContentFingerprint(3, hash), PublishedAudioVerification.verify(reader, 3, hash) { false })
        assertEquals(2, reader.stamps); assertTrue(reader.closed)
    }
    @Test fun metadataSizeMismatchDoesNotOpenDocument() {
        val reader = Reader(); reader.before = PublicationDocumentStamp(4, 1)
        assertThrows(ContentChangedException::class.java) { PublishedAudioVerification.verify(reader, 3, hash) { false } }
        assertFalse(reader.opened)
    }
    @Test fun unknownProviderSizeStillRequiresExactFullBytesAndDigest() {
        val reader = Reader(); reader.before = PublicationDocumentStamp(null, null); reader.after = reader.before
        assertEquals(hash, PublishedAudioVerification.verify(reader, 3, hash) { false }.digest)
    }
    @Test fun shortLongAndChangedPayloadNeverBecomeVerified() {
        for (payload in listOf("ab", "abcd", "abd")) {
            val reader = Reader(); reader.payload = payload.toByteArray()
            assertThrows(ContentChangedException::class.java) { PublishedAudioVerification.verify(reader, 3, hash) { false } }
            assertTrue(reader.closed)
        }
    }
    @Test fun modifiedOrResizedDocumentAfterReadIsRejected() {
        for (stamp in listOf(PublicationDocumentStamp(3, 2), PublicationDocumentStamp(4, 1))) {
            val reader = Reader(); reader.after = stamp
            assertThrows(ContentChangedException::class.java) { PublishedAudioVerification.verify(reader, 3, hash) { false } }
        }
    }
    @Test fun lostParentOrPermissionAfterReadIsNotSuccessful() {
        for (failure in listOf(SecurityException(), IOException(), ContentChangedException())) {
            val reader = Reader(); reader.secondFailure = failure
            assertThrows(failure.javaClass) { PublishedAudioVerification.verify(reader, 3, hash) { false } }
            assertTrue(reader.closed)
        }
    }
    @Test fun closeFailureDoesNotSkipReadbackFailure() {
        val reader = Reader(); reader.failClose = true
        assertThrows(IOException::class.java) { PublishedAudioVerification.verify(reader, 3, hash) { false } }
        assertEquals(1, reader.stamps)
    }
    @Test fun cancellationBeforeIOAndAfterReadCannotReturnEvidence() {
        val reader = Reader()
        assertThrows(CancellationException::class.java) { PublishedAudioVerification.verify(reader, 3, hash) { true } }
        assertFalse(reader.opened)
        assertThrows(CancellationException::class.java) { PublishedAudioVerification.verify(reader, 3, hash) { reader.closed } }
        assertTrue(reader.closed)
    }
    @Test fun invalidLimitsAndDigestDoNotOpenProvider() {
        for (size in listOf(0L, -1L, 8L * 1024 * 1024 * 1024 + 1)) {
            val reader = Reader()
            assertThrows(IllegalArgumentException::class.java) { PublishedAudioVerification.verify(reader, size, hash) { false } }
            assertFalse(reader.opened)
        }
        assertThrows(IllegalArgumentException::class.java) { PublishedAudioVerification.verify(Reader(), 3, "invalid") { false } }
    }
}
