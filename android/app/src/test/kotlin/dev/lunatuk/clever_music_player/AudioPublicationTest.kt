package dev.lunatuk.clever_music_player

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.CancellationException

class AudioPublicationTest {
    private val hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private val binding = AudioPublicationBinding("a".repeat(64), "b".repeat(64), "content://music/tree/root", "intent", 3, hash, "mp3", "c".repeat(64))
    private class Crash : Error()
    private class Journal : AudioPublicationJournal {
        val data = linkedMapOf<String, MutableMap<AudioPublicationPhase, AudioPublicationRecord>>()
        val events = mutableListOf<AudioPublicationPhase>()
        var fail: AudioPublicationPhase? = null
        var crash: AudioPublicationPhase? = null
        var readyCallback: () -> Unit = {}
        override fun all() = data.values.map { it.values.sortedBy { r -> r.phase.ordinal } }
        override fun save(record: AudioPublicationRecord) {
            if (fail == record.phase) throw IOException()
            data.getOrPut(record.binding.operation) { linkedMapOf() }[record.phase] = record
            events.add(record.phase)
            if (record.phase == AudioPublicationPhase.READY) readyCallback()
            if (crash == record.phase) throw Crash()
        }
        override fun retire(binding: AudioPublicationBinding) { data.remove(binding.operation) }
    }
    private inner class Documents(val journal: Journal) : AudioPublicationDocuments {
        val data = linkedMapOf<String, ByteArray>()
        var creations = 0; var writes = 0; var deletes = 0
        override val createAttempted: Boolean get() = creations > 0
        var sourceClosed = true; var outputClosed = true
        var crashCreate = false; var failClose = false; var partialWrite = false
        var found: List<String>? = null
        var mutateAfterRead = false
        var cancelAfterWrite: () -> Unit = {}
        val uri = "content://music/tree/root/document/opaque"
        override fun create(binding: AudioPublicationBinding): String {
            assertTrue(journal.all().flatten().any { it.phase == AudioPublicationPhase.CREATING })
            creations++; data[uri] = byteArrayOf()
            if (crashCreate) throw Crash()
            return uri
        }
        override fun output(record: AudioPublicationRecord): java.io.OutputStream {
            assertTrue(journal.all().flatten().contains(record)); outputClosed = false
            return object : ByteArrayOutputStream() {
                override fun write(b: ByteArray, offset: Int, length: Int) {
                    writes++
                    super.write(b, offset, if (partialWrite) minOf(1, length) else length)
                    data[record.uri!!] = toByteArray(); cancelAfterWrite()
                    if (partialWrite) throw IOException()
                }
                override fun close() { outputClosed = true; if (failClose) throw IOException() }
            }
        }
        override fun reader(record: AudioPublicationRecord) = object : PublicationDocumentReader {
            var stamps = 0
            override fun stamp(): PublicationDocumentStamp {
                assertTrue(outputClosed); assertTrue(sourceClosed)
                return PublicationDocumentStamp(data[record.uri]!!.size.toLong(), if (mutateAfterRead && ++stamps > 1) 2 else 1)
            }
            override fun open(): InputStream = ByteArrayInputStream(data[record.uri] ?: throw IOException())
        }
        override fun find(binding: AudioPublicationBinding) = found ?: data.keys.toList()
        override fun deleteProbe(record: AudioPublicationRecord) {
            assertTrue(sourceClosed); assertTrue(outputClosed)
            require(record.binding.probe && record.owned)
            val bytes = data[record.uri] ?: return
            require(bytes.size <= 4096 && bytes.contentEquals(AudioPublicationBinding.probeBytes(record.binding.id).copyOf(bytes.size)))
            deletes++; data.remove(record.uri)
        }
        fun source(bytes: ByteArray = "abc".toByteArray(), failClose: Boolean = false): InputStream {
            sourceClosed = false
            return object : ByteArrayInputStream(bytes) {
                override fun close() { sourceClosed = true; if (failClose) throw IOException() }
            }
        }
    }
    @Test fun phasesPrecedeEveryProviderEffectAndBothStreamsCloseBeforeReadback() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d)
        p.prepare(binding)
        val ready = p.publish(binding, { d.source() }) { false }
        assertEquals(AudioPublicationPhase.READY, ready.phase)
        assertTrue(ready.owned)
        assertEquals(AudioPublicationPhase.values().toList(),j.events)
        assertArrayEquals("abc".toByteArray(), d.data[d.uri])
    }
    @Test fun expiredAdmissionCanBeReboundOnlyBeforeCreateMarker() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d)
        p.prepare(binding)
        val next = binding.copy(owner = "d".repeat(64))
        p.prepare(next)
        assertThrows(AudioPublicationOwnershipLost::class.java) { p.publish(binding, { d.source() }) { false } }
        p.publish(next, { d.source() }) { false }
        assertEquals(1,d.creations)
    }
    @Test fun preCancelledWriteCreatesNoDocumentAndClosesSource() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
        assertThrows(CancellationException::class.java) { p.publish(binding, { d.source() }) { true } }
        assertTrue(d.sourceClosed); assertEquals(0,d.creations)
        assertTrue(j.all().isEmpty())
    }
    @Test fun failedAdmissionAndCreateMarkerNeverOpenAProviderWriter() {
        for (phase in listOf(AudioPublicationPhase.INTENT,AudioPublicationPhase.CREATING)) {
            val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d)
            if (phase == AudioPublicationPhase.INTENT) {
                j.fail = phase; assertThrows(IOException::class.java) { p.prepare(binding) }
            } else {
                p.prepare(binding); j.fail = phase
                assertThrows(IOException::class.java) { p.publish(binding, { d.source() }) { false } }
            }
            assertEquals(0,d.creations); assertEquals(0,d.writes)
        }
    }
    @Test fun failedUriPersistenceNeverWritesOrDeletesMusic() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
        j.fail = AudioPublicationPhase.DOCUMENT
        assertThrows(IOException::class.java) { p.publish(binding, { d.source() }) { false } }
        assertEquals(1,d.creations); assertEquals(0,d.writes); assertEquals(0,d.deletes)
        assertTrue(d.sourceClosed)
    }
    @Test fun partialOrCancelledWriteIsPreservedAndNeverReopenedForWrite() {
        for (partial in listOf(false,true)) {
            val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
            var cancel = false
            d.partialWrite = partial; if (!partial) d.cancelAfterWrite = { cancel = true }
            assertThrows(Exception::class.java) { p.publish(binding, { d.source() }) { cancel } }
            assertTrue(d.sourceClosed); assertTrue(d.outputClosed); assertEquals(0,d.deletes)
            val writes = d.writes
            if (partial) assertThrows(ContentChangedException::class.java) { p.reconcile(binding) { false } }
            else assertEquals(AudioPublicationPhase.READY,p.reconcile(binding) { false }.phase)
            assertEquals(writes,d.writes)
        }
    }
    @Test fun sourceAndOutputCloseFailuresRequireReadOnlyRecovery() {
        for (sourceFailure in listOf(false,true)) {
            val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
            d.failClose = !sourceFailure
            assertThrows(IOException::class.java) { p.publish(binding, { d.source(failClose = sourceFailure) }) { false } }
            assertFalse(j.all().single().any { it.phase == AudioPublicationPhase.READY })
            assertEquals(AudioPublicationPhase.READY,p.reconcile(binding) { false }.phase)
            assertEquals(1,d.writes); assertEquals(0,d.deletes)
        }
    }
    @Test fun changedSourceAndChangedProviderNeverBecomeReady() {
        for (badSource in listOf(false,true)) {
            val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
            d.mutateAfterRead = !badSource
            assertThrows(ContentChangedException::class.java) { p.publish(binding, { d.source(if (badSource) "abd".toByteArray() else "abc".toByteArray()) }) { false } }
            assertFalse(j.all().single().any { it.phase == AudioPublicationPhase.READY })
            assertEquals(0,d.deletes)
        }
    }
    @Test fun crashAtEveryDurablePhaseDoesNotAuthorizeASecondCreate() {
        for (phase in listOf(AudioPublicationPhase.CREATING,AudioPublicationPhase.DOCUMENT,AudioPublicationPhase.READY)) {
            val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding); j.crash = phase
            assertThrows(Crash::class.java) { p.publish(binding, { d.source() }) { false } }
            assertThrows(AudioPublicationNeedsReconciliation::class.java) { p.prepare(binding) }
            if (phase == AudioPublicationPhase.READY) {
                j.crash = null; assertEquals(AudioPublicationPhase.READY,p.reconcile(binding) { false }.phase)
            }
            assertTrue(d.creations <= 1); assertEquals(0,d.deletes)
        }
    }
    @Test fun ambiguousCreateAdoptsOnlyUniqueExactBytesReadOnlyAndCannotDeleteThem() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
        d.crashCreate = true
        assertThrows(Crash::class.java) { p.publish(binding, { d.source() }) { false } }
        d.found = emptyList()
        assertThrows(AudioPublicationNeedsReconciliation::class.java) { p.reconcile(binding) { false } }
        d.found = listOf(d.uri,d.uri + "2")
        assertThrows(AudioPublicationNeedsReconciliation::class.java) { p.reconcile(binding) { false } }
        d.found = listOf(d.uri)
        assertThrows(ContentChangedException::class.java) { p.reconcile(binding) { false } }
        d.data[d.uri] = "abc".toByteArray()
        val ready = p.reconcile(binding) { false }
        assertFalse(ready.owned); assertEquals(0,d.writes); assertEquals(0,d.deletes)
    }
    @Test fun lateCancellationDoesNotHideReadyReceipt() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
        var cancelled = false; j.readyCallback = { cancelled = true }
        assertEquals(AudioPublicationPhase.READY,p.publish(binding, { d.source() }) { cancelled }.phase)
    }
    @Test fun failedReadySaveCanRecoverWithoutOriginalPrivateSource() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
        j.fail = AudioPublicationPhase.READY
        assertThrows(IOException::class.java) { p.publish(binding, { d.source() }) { false } }
        j.fail = null
        assertEquals(AudioPublicationPhase.READY,p.reconcile(binding) { false }.phase)
        assertEquals(1,d.writes)
    }
    @Test fun acknowledgementRemovesOnlyPrivateLedgerAfterExactReceipt() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
        assertThrows(AudioPublicationNeedsReconciliation::class.java) { p.acknowledge(binding,d.uri) }
        p.publish(binding,{ d.source() }) { false }
        assertThrows(AudioPublicationCollision::class.java) { p.acknowledge(binding,d.uri + "wrong") }
        p.acknowledge(binding,d.uri)
        assertTrue(j.all().isEmpty()); assertArrayEquals("abc".toByteArray(),d.data[d.uri]); assertEquals(0,d.deletes)
    }
    @Test fun differentPublicationAndQualityCannotBypassPendingResource() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
        assertThrows(AudioPublicationCollision::class.java) { p.prepare(binding.copy(intent = "different")) }
        assertThrows(AudioPublicationNeedsReconciliation::class.java) { p.prepare(binding.copy(id = "d".repeat(64))) }
        assertThrows(AudioPublicationNeedsReconciliation::class.java) { p.prepare(binding.copy(id = "d".repeat(64),container = "flac")) }
        assertEquals(0,d.creations)
    }
    @Test fun operationAndLogicalByteQuotasApplyBeforeProviderEffects() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d)
        repeat(64) { n -> val b = binding.copy(id = n.toString(16).padStart(64,'0'),resource = n.toString(16).padStart(64,'0')); j.save(AudioPublicationRecord(b,AudioPublicationPhase.INTENT)) }
        assertThrows(AudioPublicationQuota::class.java) { p.prepare(binding) }
        j.data.clear()
        repeat(2) { n -> val b = binding.copy(id = n.toString().repeat(64),resource = n.toString().repeat(64),size = 8L * 1024 * 1024 * 1024); j.save(AudioPublicationRecord(b,AudioPublicationPhase.INTENT)) }
        assertThrows(AudioPublicationQuota::class.java) { p.prepare(binding) }
        assertEquals(0,d.creations)
    }
    @Test fun testCleanupCanUseLiveNewUriWhenDocumentJournalFails() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d)
        val bytes = AudioPublicationBinding.probeBytes(binding.id)
        val digest = StreamingContentFingerprint.read(ByteArrayInputStream(bytes),4096) { false }.digest
        val probe = binding.copy(intent = "cmp-audio-publication-probe-v1",size = 4096,digest = digest,probe = true)
        p.prepare(probe); j.fail = AudioPublicationPhase.DOCUMENT
        assertThrows(IOException::class.java) { p.publish(probe, { d.source(bytes) }) { false } }
        assertTrue(j.all().isEmpty()); assertTrue(d.data.isEmpty()); assertEquals(1,d.deletes)
    }
    @Test fun probeNonceAndCodecRejectUnsafeOrCorruptRecords() {
        val record = AudioPublicationRecord(binding,AudioPublicationPhase.DOCUMENT,"content://music/tree/root/document/x",true)
        val bytes = AudioPublicationCodec.encode(record)
        assertEquals(record,AudioPublicationCodec.decode(bytes))
        for (bad in listOf(bytes.copyOf(20),bytes + byteArrayOf(0),ByteArray(65537))) assertThrows(Exception::class.java) { AudioPublicationCodec.decode(bad) }
        assertThrows(IllegalArgumentException::class.java) { binding.copy(probe = true) }
        assertThrows(IllegalArgumentException::class.java) { binding.copy(id = "../bad") }
        assertThrows(IllegalArgumentException::class.java) { record.copy(uri = null) }
    }
    @Test fun uncreatedReleaseNeverCallsProviderAndFencesAnOldWriter() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d)
        p.prepare(binding)
        p.releaseUncreated(binding.copy(owner = "d".repeat(64)))
        assertTrue(j.all().isEmpty())
        assertThrows(AudioPublicationOwnershipLost::class.java) { p.publish(binding,{ d.source() }) { false } }
        assertEquals(0,d.creations); assertEquals(0,d.writes); assertEquals(0,d.deletes)
    }
    @Test fun releaseRefusesEveryPhaseThatMayHaveReachedAProvider() {
        for (phase in listOf(AudioPublicationPhase.CREATING, AudioPublicationPhase.DOCUMENT, AudioPublicationPhase.READY)) {
            val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d); p.prepare(binding)
            j.save(AudioPublicationRecord(binding,phase,if (phase == AudioPublicationPhase.CREATING) null else d.uri))
            val before = j.all()
            assertThrows(AudioPublicationNeedsReconciliation::class.java) { p.releaseUncreated(binding) }
            assertEquals(before,j.all()); assertEquals(0,d.deletes); assertEquals(0,d.creations)
        }
    }
    @Test fun releaseRejectsUnknownOrDifferentPublication() {
        val j = Journal(); val d = Documents(j); val p = AudioPublication(j,d)
        assertThrows(AudioPublicationCollision::class.java) { p.releaseUncreated(binding) }
        p.prepare(binding)
        for (changed in listOf(binding.copy(intent = "other"),binding.copy(tree = "content://other/tree/root"),
            binding.copy(size = 4), binding.copy(id = "d".repeat(64)))) {
            assertThrows(AudioPublicationCollision::class.java) { p.releaseUncreated(changed) }
        }
        assertEquals(1,j.all().size)
    }
    private fun probe(id: String): AudioPublicationBinding {
        val bytes = AudioPublicationBinding.probeBytes(id)
        return binding.copy(id = id,owner = id,probe = true,intent = "cmp-audio-publication-probe-v1",size = 4096,
            digest = StreamingContentFingerprint.read(ByteArrayInputStream(bytes),4096) { false }.digest)
    }
    @Test fun explicitRecoveryCheckExercisesUncreatedFullAndPartialWithClosedStreams() {
        val j = Journal(); val d = Documents(j); var n = 0; var sources = 0; var adapters = 0
        val checked = AudioPublicationRecoveryCheck(j) { adapters++; d }.run(
            { probe((++n).toString(16).padStart(64,'0')) },
            { b -> sources++; d.source(AudioPublicationBinding.probeBytes(b.id)) }, { false })
        assertEquals(3,checked); assertEquals(2,sources); assertEquals(5,adapters)
        assertEquals(2,d.creations); assertEquals(2,d.writes); assertEquals(2,d.deletes)
        assertTrue(j.all().isEmpty()); assertTrue(d.data.isEmpty()); assertTrue(d.sourceClosed); assertTrue(d.outputClosed)
    }
    @Test fun recoveryCheckCannotUseRealMusicOrRunAfterCancellation() {
        val j = Journal(); val d = Documents(j)
        val check = AudioPublicationRecoveryCheck(j) { d }
        assertThrows(IllegalArgumentException::class.java) { check.run({ binding }, { d.source() }, { false }) }
        assertThrows(CancellationException::class.java) { check.run({ probe(binding.id) }, { d.source() }, { true }) }
        assertTrue(j.all().isEmpty()); assertEquals(0,d.creations)
    }
    @Test fun failedRecoveryCheckDoesNotReportSuccessAndClosesSource() {
        val j = Journal(); val d = Documents(j); var n = 0
        assertThrows(IOException::class.java) {
            AudioPublicationRecoveryCheck(j) { d }.run({ probe((++n).toString().padStart(64,'0')) },
                { b -> d.source(AudioPublicationBinding.probeBytes(b.id), failClose = true) }, { false })
        }
        assertTrue(d.sourceClosed); assertTrue(d.outputClosed)
        assertTrue(j.all().isEmpty()); assertTrue(d.data.isEmpty())
    }

}
