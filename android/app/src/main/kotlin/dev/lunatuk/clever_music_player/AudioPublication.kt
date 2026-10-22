package dev.lunatuk.clever_music_player

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CancellationException

internal enum class AudioPublicationPhase { INTENT, CREATING, DOCUMENT, READY }

internal data class AudioPublicationBinding(val resource: String, val id: String,
    val tree: String, val intent: String, val size: Long, val digest: String,
    val container: String, val owner: String, val probe: Boolean = false) {
    init {
        require(listOf(resource, id, digest, owner).all { it.matches(Regex("[0-9a-f]{64}")) })
        require(tree.length in 1..8192 && tree.startsWith("content://"))
        require(intent.toByteArray(Charsets.UTF_8).size in 1..16384)
        require(size in 1..(8L * 1024 * 1024 * 1024))
        require(container in setOf("mp3", "m4a", "flac"))
        if (probe) {
            require(intent == "cmp-audio-publication-probe-v1" && size == 4096L && container == "mp3")
            require(digest == StreamingContentFingerprint.read(ByteArrayInputStream(probeBytes(id)), 4096) { false }.digest)
        }
    }
    val operation: String get() = "$resource-$id"
    val name: String get() = "cmp-$operation.$container"
    fun samePublication(other: AudioPublicationBinding): Boolean = copy(owner = other.owner) == other
    companion object {
        fun probeBytes(id: String): ByteArray {
            val marker = "Clever Music Player publication check v1:$id\n"
            return ByteArray(4096) { marker[it % marker.length].code.toByte() }
        }
    }
}

internal data class AudioPublicationRecord(val binding: AudioPublicationBinding,
    val phase: AudioPublicationPhase, val uri: String? = null, val owned: Boolean = false) {
    init {
        require((phase.ordinal >= AudioPublicationPhase.DOCUMENT.ordinal) == (uri != null))
        require(uri == null || uri.length in 1..8192)
        require(!owned || uri != null)
    }
}

internal object AudioPublicationCodec {
    fun encode(record: AudioPublicationRecord): ByteArray = ByteArrayOutputStream().also { bytes ->
        DataOutputStream(bytes).use { out ->
            val b = record.binding
            out.writeInt(0x434d5031); out.writeInt(1)
            for (value in listOf(b.resource, b.id, b.tree, b.intent, b.digest, b.container, b.owner)) out.writeUTF(value)
            out.writeLong(b.size); out.writeBoolean(b.probe); out.writeInt(record.phase.ordinal)
            out.writeBoolean(record.uri != null); record.uri?.let(out::writeUTF)
            out.writeBoolean(record.owned)
        }
    }.toByteArray().also { require(it.size <= 65536) }
    fun decode(bytes: ByteArray): AudioPublicationRecord {
        require(bytes.size <= 65536)
        return DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            require(input.readInt() == 0x434d5031 && input.readInt() == 1)
            val values = List(7) { input.readUTF() }
            val size = input.readLong(); val probe = input.readBoolean()
            val phase = AudioPublicationPhase.values()[input.readInt()]
            val uri = if (input.readBoolean()) input.readUTF() else null
            val record = AudioPublicationRecord(AudioPublicationBinding(values[0], values[1], values[2], values[3],
                size, values[4], values[5], values[6], probe), phase, uri, input.readBoolean())
            require(input.read() == -1)
            record
        }
    }
}

internal interface AudioPublicationJournal {
    fun all(): List<List<AudioPublicationRecord>>
    /** A complete, durable phase before the next provider effect. */
    fun save(record: AudioPublicationRecord)
    /** Remove intent first, ready last; never delete provider documents. */
    fun retire(binding: AudioPublicationBinding)
}
internal interface AudioPublicationDocuments {
    /** Default conservative for adapters that cannot prove no create call. */
    val createAttempted: Boolean get() = true
    /** New ID, absent from the pre-create snapshot; exact name and parent. */
    fun create(binding: AudioPublicationBinding): String
    /** Only a freshly created document in this live operation can be opened. */
    fun output(record: AudioPublicationRecord): OutputStream
    fun reader(record: AudioPublicationRecord): PublicationDocumentReader
    /** Read-only recovery. Ambiguous results must not be guessed. */
    fun find(binding: AudioPublicationBinding): List<String>
    fun deleteProbe(record: AudioPublicationRecord) // known, app-owned test only
}

internal class AudioPublicationNeedsReconciliation : Exception()
internal class AudioPublicationCollision : Exception()
internal class AudioPublicationOwnershipLost : Exception()
internal class AudioPublicationQuota : Exception()

/** No provider effects inside admission. Caller fences this short private IO. */
internal class AudioPublication(private val journal: AudioPublicationJournal,
    private val documents: AudioPublicationDocuments) {
    private fun records(binding: AudioPublicationBinding): List<AudioPublicationRecord> =
        journal.all().firstOrNull { it.first().binding.operation == binding.operation } ?: emptyList()

    fun prepare(binding: AudioPublicationBinding) {
        val all = journal.all()
        val current = all.firstOrNull { it.first().binding.operation == binding.operation }
        if (current != null) {
            if (!current.first().binding.samePublication(binding)) throw AudioPublicationCollision()
            if (current.any { it.phase != AudioPublicationPhase.INTENT }) throw AudioPublicationNeedsReconciliation()
            // No create marker: an old owner can no longer use its old admission.
            journal.save(AudioPublicationRecord(binding, AudioPublicationPhase.INTENT))
            return
        }
        if (all.any { it.first().binding.resource == binding.resource && it.first().binding.tree == binding.tree }) {
            throw AudioPublicationNeedsReconciliation()
        }
        if (all.size >= 64 || all.filter { group -> group.none { it.phase == AudioPublicationPhase.READY } }
                .sumOf { it.first().binding.size } > 16L * 1024 * 1024 * 1024 - binding.size) throw AudioPublicationQuota()
        journal.save(AudioPublicationRecord(binding, AudioPublicationPhase.INTENT))
    }

    fun publish(binding: AudioPublicationBinding, source: () -> InputStream,
        cancelled: () -> Boolean): AudioPublicationRecord {
        val records = records(binding)
        if (records.size != 1 || records.single() != AudioPublicationRecord(binding, AudioPublicationPhase.INTENT)) {
            throw AudioPublicationOwnershipLost()
        }
        fun check() { if (cancelled()) throw CancellationException() }
        var document: AudioPublicationRecord? = null
        try {
            source().use { input ->
                check()
                journal.save(AudioPublicationRecord(binding, AudioPublicationPhase.CREATING))
                check()
                val uri = documents.create(binding)
                val created = AudioPublicationRecord(binding, AudioPublicationPhase.DOCUMENT, uri, owned = true)
                document = created
                journal.save(created)
                check()
                documents.output(created).use { out ->
                    VerifiedDocumentTransfer.copy(input, out, binding.size, binding.digest, cancelled)
                }
            } // close both streams before readback or any success marker
            val created = document ?: throw AudioPublicationNeedsReconciliation()
            PublishedAudioVerification.verify(documents.reader(created), binding.size, binding.digest, cancelled)
            check()
            val ready = created.copy(phase = AudioPublicationPhase.READY)
            journal.save(ready)
            return ready // late cancellation cannot erase a durably verified result
        } catch (error: Exception) {
            if (document == null && !documents.createAttempted) {
                // This live owner knows no provider mutation was invoked.
                // A crash bypasses this path and keeps the ambiguous marker.
                try { journal.retire(binding) } catch (_: Exception) { /* preserve */ }
            }
            // A live check still knows the new URI if its journal save failed.
            // All streams have closed. Never apply this cleanup to real music.
            if (binding.probe && document != null) {
                try { documents.deleteProbe(document!!); journal.retire(binding) }
                catch (_: Exception) { /* preserve state for explicit recovery */ }
            }
            throw error
        }
    }

    fun reconcile(binding: AudioPublicationBinding, cancelled: () -> Boolean): AudioPublicationRecord {
        val records = records(binding)
        if (records.isEmpty() || !records.first().binding.samePublication(binding)) throw AudioPublicationCollision()
        val created = records.lastOrNull { it.phase.ordinal >= AudioPublicationPhase.DOCUMENT.ordinal }
        val candidate = if (created != null) created else {
            if (records.none { it.phase == AudioPublicationPhase.CREATING }) throw AudioPublicationNeedsReconciliation()
            val matches = documents.find(binding)
            if (matches.size != 1) throw AudioPublicationNeedsReconciliation()
            // Name AND exact full bytes permit read-only adoption, never deletion.
            AudioPublicationRecord(records.first().binding, AudioPublicationPhase.DOCUMENT, matches.single(), owned = false)
        }
        PublishedAudioVerification.verify(documents.reader(candidate), binding.size, binding.digest, cancelled)
        if (cancelled()) throw CancellationException()
        if (created == null) journal.save(candidate)
        val ready = candidate.copy(phase = AudioPublicationPhase.READY)
        journal.save(ready)
        return ready
    }

    fun acknowledge(binding: AudioPublicationBinding, uri: String) {
        val ready = records(binding).lastOrNull { it.phase == AudioPublicationPhase.READY }
            ?: throw AudioPublicationNeedsReconciliation()
        if (!ready.binding.samePublication(binding) || ready.uri != uri) throw AudioPublicationCollision()
        journal.retire(ready.binding)
    }

    fun cleanupProbe(binding: AudioPublicationBinding) {
        require(binding.probe)
        val records = records(binding)
        if (records.size == 1 && records.single().phase == AudioPublicationPhase.INTENT) {
            journal.retire(binding)
            return
        }
        val created = records.lastOrNull { it.uri != null } ?: throw AudioPublicationNeedsReconciliation()
        require(created.binding == binding && created.owned)
        documents.deleteProbe(created)
        journal.retire(binding)
    }
}
