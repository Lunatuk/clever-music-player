package dev.lunatuk.clever_music_player

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.CancellationException

/** URI is recorded before opening for write. A null URI is an ambiguous create,
 * never permission to search for and delete a file by its name. */
internal data class DestinationProbeRecord(val id: String, val tree: String, val uri: String?) {
    init {
        require(id.matches(Regex("[0-9a-f]{32}")))
        require(tree.length in 1..8192 && (uri == null || uri.length in 1..8192))
    }
    val name: String get() = ".cmp-write-$id.tmp"
    fun bytes(): ByteArray {
        val marker = "Clever Music Player storage check v1:$id\n"
        return ByteArray(4096) { marker[it % marker.length].code.toByte() }
    }
}

/** Private, bounded, versioned journal. Unknown/corrupt entries block mutation. */
internal object DestinationProbeCodec {
    fun encode(record: DestinationProbeRecord): ByteArray = ByteArrayOutputStream().also { bytes ->
        DataOutputStream(bytes).use { out ->
            out.writeInt(1)
            out.writeUTF(record.id)
            out.writeUTF(record.tree)
            out.writeBoolean(record.uri != null)
            record.uri?.let(out::writeUTF)
        }
    }.toByteArray().also { require(it.size <= 32768) }

    fun decode(bytes: ByteArray): DestinationProbeRecord {
        require(bytes.size <= 32768)
        return DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            require(input.readInt() == 1)
            val record = DestinationProbeRecord(input.readUTF(), input.readUTF(),
                if (input.readBoolean()) input.readUTF() else null)
            require(input.read() == -1)
            record
        }
    }
}

internal interface DestinationProbeJournal {
    fun records(): List<DestinationProbeRecord>
    fun save(record: DestinationProbeRecord)
    fun remove(record: DestinationProbeRecord)
}

/** Implementations must validate grants, parent membership and exact name on
 * every operation. create returns only a new document, never an existing URI. */
internal interface DestinationProbeDocuments {
    fun create(record: DestinationProbeRecord): String
    fun exists(record: DestinationProbeRecord): Boolean
    fun output(record: DestinationProbeRecord): OutputStream
    fun input(record: DestinationProbeRecord, cleanup: Boolean = false): InputStream
    fun delete(record: DestinationProbeRecord)
}

/** Reusable bounded transfer. Caller closes both streams before readback. */
internal object VerifiedDocumentTransfer {
    fun copy(input: InputStream, output: OutputStream, size: Long, digest: String,
             cancelled: () -> Boolean) {
        require(size in 1..(8L * 1024 * 1024 * 1024))
        require(digest.matches(Regex("[0-9a-f]{64}")))
        val tee = object : InputStream() {
            var copied = 0L
            override fun read(): Int = throw UnsupportedOperationException()
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                val count = input.read(buffer, offset, length)
                if (cancelled()) throw CancellationException()
                if (count > 0) {
                    if (count > size - copied) throw ContentChangedException()
                    output.write(buffer, offset, count)
                    copied += count
                }
                return count
            }
        }
        val actual = StreamingContentFingerprint.read(tee, size, cancelled)
        if (actual.digest != digest) throw ContentChangedException()
        output.flush()
    }
}

internal data class DestinationCheckResult(val status: String, val stage: Int,
    val verifiedBytes: Int = 0, val recovered: Int = 0, val retained: Int = 0)

/** The probe contains no music. Recovery only removes a known URI containing
 * exactly this nonce-marked payload; partial or changed files are preserved. */
internal class DownloadDestinationCheck(private val journal: DestinationProbeJournal,
    private val documents: DestinationProbeDocuments,
    private val newId: () -> String = { UUID.randomUUID().toString().replace("-", "") }) {
    fun run(tree: String, cancelled: () -> Boolean): DestinationCheckResult {
        var stage = 0
        var recovered = 0
        var retained = 0
        var current: DestinationProbeRecord? = null
        var verified = 0
        try {
            checkCancellation(cancelled)
            val records = journal.records()
            require(records.size <= 64)
            stage = 1
            for (record in records.filter { it.tree == tree }) {
                checkCancellation(cancelled)
                val cleaned = try { recover(record) } catch (_: Exception) { false }
                if (cleaned) recovered++ else retained++
            }
            if (retained > 0) return DestinationCheckResult("retained", stage, recovered = recovered, retained = retained)
            if (records.size - recovered >= 64) return DestinationCheckResult("retained", stage, recovered = recovered, retained = 64)
            stage = 2
            val intent = DestinationProbeRecord(newId(), tree, null)
            require(records.none { it.id == intent.id && it.tree != tree })
            journal.save(intent)
            current = intent
            checkCancellation(cancelled)
            stage = 3
            val record = intent.copy(uri = documents.create(intent))
            // If this save fails, cleanup still uses the live, validated URI.
            current = record
            journal.save(record)
            checkCancellation(cancelled)
            stage = 4
            val payload = record.bytes()
            val digest = StreamingContentFingerprint.read(ByteArrayInputStream(payload), 4096) { false }.digest
            documents.output(record).use { output ->
                ByteArrayInputStream(payload).use { input ->
                    VerifiedDocumentTransfer.copy(input, output, 4096, digest, cancelled)
                }
            }
            stage = 5
            documents.input(record).use { input ->
                val actual = StreamingContentFingerprint.read(input, 4096, cancelled)
                if (actual.digest != digest) throw ContentChangedException()
            }
            verified = 4096
            checkCancellation(cancelled)
            stage = 6
            documents.delete(record)
            journal.remove(record)
            current = null
            return DestinationCheckResult(if (cancelled()) "cancelled" else "ready", stage, verified, recovered)
        } catch (error: Exception) {
            val record = current
            if (record != null) {
                val cleaned = try {
                    if (record.uri == null) {
                        // No create attempted yet: safe to retire the intent.
                        if (stage < 3) { journal.remove(record); true } else false
                    } else cleanupLive(record)
                } catch (_: Exception) { false }
                if (!cleaned) retained++
            }
            val status = when {
                retained > 0 -> "retained"
                cancelled() || error is CancellationException -> "cancelled"
                error is SecurityException -> "accessDenied"
                error is UnsupportedOperationException -> "unsupported"
                else -> "io"
            }
            return DestinationCheckResult(status, stage, verified, recovered, retained)
        }
    }

    private fun recover(record: DestinationProbeRecord): Boolean {
        if (record.uri == null) return false
        if (!documents.exists(record)) { journal.remove(record); return true }
        val expected = StreamingContentFingerprint.read(ByteArrayInputStream(record.bytes()), 4096) { false }
        try {
            documents.input(record, cleanup = true).use {
                if (StreamingContentFingerprint.read(it, 4096) { false } != expected) return false
            }
        } catch (_: ContentChangedException) { return false }
        documents.delete(record)
        journal.remove(record)
        return true
    }

    private fun cleanupLive(record: DestinationProbeRecord): Boolean {
        if (documents.exists(record)) {
            // Only the prefix of our known payload is safe after an interrupted
            // live write; changed/overlong provider contents remain untouched.
            val payload = record.bytes()
            documents.input(record, cleanup = true).use { input ->
                var count = 0
                val buffer = ByteArray(4096)
                var empty = 0
                while (true) {
                    val length = input.read(buffer)
                    if (length < 0) break
                    if (length == 0) { if (++empty >= 16) return false; continue }
                    empty = 0
                    if (length > payload.size - count) return false
                    for (index in 0 until length) if (buffer[index] != payload[count + index]) return false
                    count += length
                }
            }
            documents.delete(record)
        }
        journal.remove(record)
        return true
    }

    private fun checkCancellation(cancelled: () -> Boolean) {
        if (cancelled()) throw CancellationException()
    }
}
