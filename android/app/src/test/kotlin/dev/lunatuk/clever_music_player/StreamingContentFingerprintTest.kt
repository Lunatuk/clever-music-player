package dev.lunatuk.clever_music_player

import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Test

class StreamingContentFingerprintTest {
    @Test fun knownSha256() {
        val result = StreamingContentFingerprint.read(ByteArrayInputStream("abc".toByteArray()), 3) { false }
        assertEquals(3L, result.sizeBytes)
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", result.digest)
    }
    @Test fun multiplePartialBuffers() {
        val bytes = ByteArray(700000) { (it % 251).toByte() }
        val stream = object : ByteArrayInputStream(bytes) {
            override fun read(buffer: ByteArray, offset: Int, length: Int) = super.read(buffer, offset, minOf(length, 137))
        }
        val result = StreamingContentFingerprint.read(stream, bytes.size.toLong()) { false }
        val expected = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        assertEquals(expected, result.digest)
    }
    @Test(expected = ContentChangedException::class) fun shorterRead() {
        StreamingContentFingerprint.read(ByteArrayInputStream(byteArrayOf(1)), 2) { false }
    }
    @Test(expected = ContentChangedException::class) fun longerRead() {
        StreamingContentFingerprint.read(ByteArrayInputStream(byteArrayOf(1, 2)), 1) { false }
    }
    @Test(expected = ContentChangedException::class) fun emptyRead() {
        StreamingContentFingerprint.read(ByteArrayInputStream(byteArrayOf()), 1) { false }
    }
    @Test(expected = CancellationException::class) fun cancelledBeforeReading() {
        val stream = object : InputStream() {
            override fun read(): Int = throw AssertionError("Must not read")
        }
        StreamingContentFingerprint.read(stream, 1) { true }
    }
    @Test(expected = CancellationException::class) fun cancelledDuringReading() {
        var cancelled = false
        val stream = object : ByteArrayInputStream(byteArrayOf(1, 2)) {
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                cancelled = true
                return super.read(buffer, offset, length)
            }
        }
        StreamingContentFingerprint.read(stream, 2) { cancelled }
    }
    @Test fun stalledProviderStopsAfterBoundedEmptyReads() {
        var reads = 0
        val stream = object : InputStream() {
            override fun read() = 0
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int { reads++; return 0 }
        }
        try {
            StreamingContentFingerprint.read(stream, Long.MAX_VALUE) { false }
            fail("Expected IOException")
        } catch (_: IOException) { assertEquals(16, reads) }
    }
    @Test(expected = IllegalArgumentException::class) fun positiveExpectedSizeRequired() {
        StreamingContentFingerprint.read(ByteArrayInputStream(byteArrayOf()), 0) { false }
    }
}
