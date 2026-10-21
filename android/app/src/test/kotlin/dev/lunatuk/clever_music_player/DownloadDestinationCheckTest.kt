package dev.lunatuk.clever_music_player

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.CancellationException

class DownloadDestinationCheckTest {
    private val tree = "content://provider/tree/music"
    private val id = "a".repeat(32)
    private val record get() = DestinationProbeRecord(id, tree, "content://provider/tree/music/document/test")
    private class Crash : Error()
    private class Journal : DestinationProbeJournal {
        val data = linkedMapOf<String, DestinationProbeRecord>()
        val events = mutableListOf<String>()
        var failSave = 0
        var saves = 0
        var failRemove = false
        override fun records() = data.values.toList()
        override fun save(record: DestinationProbeRecord) {
            events.add(if (record.uri == null) "intent" else "uri")
            if (++saves == failSave) throw IOException()
            data[record.id] = record
        }
        override fun remove(record: DestinationProbeRecord) {
            if (failRemove) throw IOException()
            data.remove(record.id)
        }
    }
    private inner class Documents(private val journal: Journal) : DestinationProbeDocuments {
        val data = linkedMapOf<String, ByteArray>()
        var outputClosed = true
        var crashCreate = false
        var crashRead = false
        var failClose = false
        var failDelete = false
        var failCreate = false
        var failPartialWrite = false
        var corrupt = false
        var revoked = false
        var afterWrite: () -> Unit = {}
        var creations = 0
        var deletions = 0
        override fun create(record: DestinationProbeRecord): String {
            assertNull(journal.data[record.id]!!.uri)
            creations++
            if (failCreate) throw IOException()
            data[this@DownloadDestinationCheckTest.record.uri!!] = byteArrayOf()
            if (crashCreate) throw Crash()
            return this@DownloadDestinationCheckTest.record.uri!!
        }
        override fun exists(record: DestinationProbeRecord): Boolean {
            if (revoked) throw SecurityException()
            return data.containsKey(record.uri)
        }
        override fun output(record: DestinationProbeRecord): java.io.OutputStream {
            assertEquals(record, journal.data[record.id])
            outputClosed = false
            return object : ByteArrayOutputStream() {
                override fun write(buffer: ByteArray, offset: Int, length: Int) {
                    if (failPartialWrite) {
                        super.write(buffer, offset, minOf(length, 13))
                        data[record.uri!!] = toByteArray()
                        throw IOException()
                    }
                    super.write(buffer, offset, length)
                    data[record.uri!!] = toByteArray()
                    afterWrite()
                }
                override fun close() {
                    outputClosed = true
                    if (corrupt) data[record.uri!!] = byteArrayOf(1, 2, 3)
                    if (failClose) throw IOException()
                }
            }
        }
        override fun input(record: DestinationProbeRecord, cleanup: Boolean): InputStream {
            assertTrue(outputClosed)
            if (revoked) throw SecurityException()
            if (crashRead) throw Crash()
            return ByteArrayInputStream(data[record.uri] ?: throw IOException())
        }
        override fun delete(record: DestinationProbeRecord) {
            assertTrue(outputClosed)
            if (failDelete) throw IOException()
            deletions++
            data.remove(record.uri)
        }
    }
    private fun run(journal: Journal, documents: Documents, cancel: () -> Boolean = { false }) =
        DownloadDestinationCheck(journal, documents) { id }.run(tree, cancel)

    @Test fun successfulWriteClosesReadsBackDeletesAndRetiresJournal() {
        val journal = Journal(); val documents = Documents(journal)
        val result = run(journal, documents)
        assertEquals("ready", result.status)
        assertEquals(4096, result.verifiedBytes)
        assertEquals(listOf("intent", "uri"), journal.events)
        assertTrue(documents.data.isEmpty()); assertTrue(journal.data.isEmpty())
        assertEquals("ready", run(journal, documents).status)
    }
    @Test fun cancelBeforeAdmissionDoesNoIO() {
        val journal = Journal(); val documents = Documents(journal)
        assertEquals("cancelled", run(journal, documents) { true }.status)
        assertEquals(0, documents.creations); assertTrue(journal.events.isEmpty())
    }
    @Test fun cancelAfterWriteDrainsAndRemovesOnlyLiveKnownPayload() {
        val journal = Journal(); val documents = Documents(journal)
        var cancel = false; documents.afterWrite = { cancel = true }
        assertEquals("cancelled", run(journal, documents) { cancel }.status)
        assertTrue(documents.data.isEmpty()); assertTrue(journal.data.isEmpty())
        assertTrue(documents.outputClosed)
    }
    @Test fun closeFailureCannotReportVerifiedSuccess() {
        val journal = Journal(); val documents = Documents(journal)
        documents.failClose = true
        val result = run(journal, documents)
        assertEquals("io", result.status); assertEquals(0, result.verifiedBytes)
        assertTrue(documents.data.isEmpty()); assertTrue(journal.data.isEmpty())
    }
    @Test fun partialFailedWriteIsClosedBeforeKnownPrefixCleanup() {
        val journal = Journal(); val documents = Documents(journal)
        documents.failPartialWrite = true
        assertEquals("io", run(journal, documents).status)
        assertTrue(documents.outputClosed)
        assertTrue(documents.data.isEmpty()); assertTrue(journal.data.isEmpty())
    }
    @Test fun createFailureIsAmbiguousAndNeverRetriedBlindly() {
        val journal = Journal(); val documents = Documents(journal)
        documents.failCreate = true
        assertEquals("retained", run(journal, documents).status)
        assertEquals("retained", run(journal, documents).status)
        assertEquals(1, documents.creations)
    }
    @Test fun corruptReadbackIsRetainedWithoutDeletingForeignContent() {
        val journal = Journal(); val documents = Documents(journal)
        documents.corrupt = true
        val result = run(journal, documents)
        assertEquals("retained", result.status); assertEquals(1, result.retained)
        assertEquals(0, documents.deletions); assertEquals(1, journal.data.size)
    }
    @Test fun deleteFailureRetainsReceiptAndNextCheckRecoversIt() {
        val journal = Journal(); val documents = Documents(journal)
        documents.failDelete = true
        val failed = run(journal, documents)
        assertEquals("retained", failed.status); assertEquals(4096, failed.verifiedBytes)
        documents.failDelete = false
        val next = run(journal, documents)
        assertEquals("ready", next.status); assertEquals(1, next.recovered)
    }
    @Test fun killAfterCreateKeepsAmbiguousIntentAndNeverSearchesByName() {
        val journal = Journal(); val documents = Documents(journal)
        documents.crashCreate = true
        assertThrows(Crash::class.java) { run(journal, documents) }
        documents.crashCreate = false
        assertEquals("retained", run(journal, documents).status)
        assertEquals(1, documents.creations); assertEquals(0, documents.deletions)
    }
    @Test fun killAfterOutputCloseRecoversExactPayloadIdempotently() {
        val journal = Journal(); val documents = Documents(journal)
        documents.crashRead = true
        assertThrows(Crash::class.java) { run(journal, documents) }
        documents.crashRead = false
        assertEquals(1, run(journal, documents).recovered)
        assertEquals(0, run(journal, documents).recovered)
    }
    @Test fun recoveryPreservesPartialChangedAndOverlongFiles() {
        for (payload in listOf(byteArrayOf(), record.bytes().copyOf(10),
            record.bytes() + byteArrayOf(1), ByteArray(4096))) {
            val journal = Journal(); val documents = Documents(journal)
            journal.data[id] = record; documents.data[record.uri!!] = payload
            assertEquals("retained", run(journal, documents).status)
            assertEquals(0, documents.creations); assertEquals(0, documents.deletions)
            assertArrayEquals(payload, documents.data[record.uri])
        }
    }
    @Test fun missingDocumentRetiresOnlyItsReceipt() {
        val journal = Journal(); val documents = Documents(journal)
        journal.data[id] = record
        assertEquals(1, run(journal, documents).recovered)
    }
    @Test fun revokedGrantDoesNotClassifyFileAsMissing() {
        val journal = Journal(); val documents = Documents(journal)
        journal.data[id] = record; documents.revoked = true
        assertEquals("retained", run(journal, documents).status)
        assertEquals(record, journal.data[id]); assertEquals(0, documents.creations)
    }
    @Test fun failedUriPersistenceCleansLiveFileBeforeRetiringIntent() {
        val journal = Journal(); val documents = Documents(journal)
        journal.failSave = 2
        assertEquals("io", run(journal, documents).status)
        assertTrue(documents.data.isEmpty()); assertTrue(journal.data.isEmpty())
    }
    @Test fun failedIntentPersistenceNeverCreatesDocument() {
        val journal = Journal(); val documents = Documents(journal)
        journal.failSave = 1
        assertEquals("io", run(journal, documents).status)
        assertEquals(0, documents.creations)
    }
    @Test fun journalRetirementFailureIsNotSuccessAndCanRecoverMissingFile() {
        val journal = Journal(); val documents = Documents(journal)
        journal.failRemove = true
        assertEquals("retained", run(journal, documents).status)
        assertTrue(documents.data.isEmpty()); assertEquals(1, journal.data.size)
        journal.failRemove = false
        assertEquals(1, run(journal, documents).recovered)
    }
    @Test fun codecRejectsUnknownVersionsTruncationTrailingDataAndUnsafeIds() {
        assertEquals(record, DestinationProbeCodec.decode(DestinationProbeCodec.encode(record)))
        val bytes = DestinationProbeCodec.encode(record)
        for (bad in listOf(bytes.copyOf(5), bytes + byteArrayOf(0), ByteArray(32769), byteArrayOf(0,0,0,2))) {
            assertThrows(Exception::class.java) { DestinationProbeCodec.decode(bad) }
        }
        assertThrows(IllegalArgumentException::class.java) { record.copy(id = "../outside") }
    }
    @Test fun recoveryDoesNotTouchAnotherDestination() {
        val journal = Journal(); val documents = Documents(journal)
        journal.data["b".repeat(32)] = record.copy(id = "b".repeat(32), tree = "content://other/tree/x")
        assertEquals("ready", run(journal, documents).status)
        assertEquals(1, journal.data.size)
    }
    @Test fun fullJournalBlocksNewCreates() {
        val journal = Journal(); val documents = Documents(journal)
        repeat(64) { number ->
            val other = record.copy(id = number.toString(16).padStart(32, '0'), tree = "other")
            journal.data[other.id] = other
        }
        assertEquals("retained", run(journal, documents).status)
        assertEquals(0, documents.creations)
    }
    @Test fun transferRejectsShortLongWrongDigestAndNoProgress() {
        val payload = record.bytes()
        val digest = StreamingContentFingerprint.read(ByteArrayInputStream(payload), 4096) { false }.digest
        for (input in listOf(ByteArrayInputStream(payload.copyOf(4095)),
            ByteArrayInputStream(payload + byteArrayOf(1)), ByteArrayInputStream(ByteArray(4096)),
            object : InputStream() { override fun read() = 0; override fun read(b: ByteArray, o: Int, l: Int) = 0 })) {
            val output = ByteArrayOutputStream()
            assertThrows(IOException::class.java) { VerifiedDocumentTransfer.copy(input, output, 4096, digest) { false } }
            assertTrue(output.size() <= 4096)
        }
    }
    @Test fun transferHonoursCancellationAndMemoryBound() {
        val payload = record.bytes()
        val digest = StreamingContentFingerprint.read(ByteArrayInputStream(payload), 4096) { false }.digest
        assertThrows(CancellationException::class.java) {
            VerifiedDocumentTransfer.copy(ByteArrayInputStream(payload), ByteArrayOutputStream(), 4096, digest) { true }
        }
        assertThrows(IllegalArgumentException::class.java) {
            VerifiedDocumentTransfer.copy(ByteArrayInputStream(payload), ByteArrayOutputStream(), 9L * 1024 * 1024 * 1024, digest) { false }
        }
    }
    @Test fun transferStreamsManyChunksWithoutBufferingWholeSource() {
        val payload = ByteArray(512 * 1024) { (it % 251).toByte() }
        val digest = StreamingContentFingerprint.read(ByteArrayInputStream(payload), payload.size.toLong()) { false }.digest
        val input = object : ByteArrayInputStream(payload) {
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                assertTrue(len <= 64 * 1024)
                return super.read(b, off, minOf(len, 117))
            }
        }
        val output = ByteArrayOutputStream()
        VerifiedDocumentTransfer.copy(input, output, payload.size.toLong(), digest) { false }
        assertArrayEquals(payload, output.toByteArray())
    }
}
