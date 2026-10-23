package dev.lunatuk.clever_music_player

import java.io.FilterOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CancellationException

/** Explicit, nonce-marked probe only. Faults are local control-flow interruptions,
 * not a claim to simulate an OS crash or a provider losing power. */
internal class AudioPublicationRecoveryCheck(private val journal: AudioPublicationJournal,
    private val documents: () -> AudioPublicationDocuments) {
    private class Interrupted : Error()

    fun run(binding: () -> AudioPublicationBinding,
        source: (AudioPublicationBinding) -> InputStream,
        cancelled: () -> Boolean): Int {
        var passed = 0
        for (scenario in 0..2) {
            if (cancelled()) throw CancellationException()
            val b = binding()
            require(b.probe)
            val docs = documents()
            val ordinary = AudioPublication(journal, docs)
            ordinary.prepare(b)
            try {
                if (scenario == 0) {
                    ordinary.releaseUncreated(b.copy(owner = "e".repeat(64)))
                } else {
                    val interrupted = object : AudioPublicationDocuments by docs {
                        override fun reader(record: AudioPublicationRecord): PublicationDocumentReader {
                            // Full bytes and both closes, but no successful readback/READY.
                            throw Interrupted()
                        }
                        override fun output(record: AudioPublicationRecord): OutputStream {
                            val output = docs.output(record)
                            if (scenario == 1) return output
                            return object : FilterOutputStream(output) {
                                override fun write(bytes: ByteArray, offset: Int, length: Int) {
                                    out.write(bytes, offset, minOf(length, 2048))
                                    throw Interrupted()
                                }
                                override fun write(value: Int) { out.write(value); throw Interrupted() }
                            }
                        }
                    }
                    var stopped = false
                    try { AudioPublication(journal, interrupted).publish(b, { source(b) }, cancelled) }
                    catch (_: Interrupted) { stopped = true }
                    check(stopped)
                    // Fresh adapter has no live-write capability; the source is
                    // never supplied to recovery. Original binding remains in journal.
                    val recovery = AudioPublication(journal, documents())
                    val next = b.copy(owner = "f".repeat(64))
                    if (scenario == 1) {
                        check(recovery.reconcile(next, cancelled).phase == AudioPublicationPhase.READY)
                    } else {
                        var rejected = false
                        try { recovery.reconcile(next, cancelled) }
                        catch (_: ContentChangedException) { rejected = true }
                        check(rejected)
                        check(journal.all().first { it.first().binding.operation == b.operation }
                            .none { it.phase == AudioPublicationPhase.READY })
                    }
                    recovery.cleanupProbe(b)
                }
                check(journal.all().none { it.first().binding.operation == b.operation })
                passed++
            } finally {
                // Known test data only. A failed or uncertain cleanup remains
                // in the ledger and is reported by the outer qualification.
                if (journal.all().any { it.first().binding.operation == b.operation }) {
                    ordinary.cleanupProbe(b)
                }
            }
        }
        return passed
    }
}
