package dev.lunatuk.clever_music_player

import android.util.AtomicFile
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.io.FileInputStream
import java.io.IOException

internal fun readAudioPublicationFile(file: File): ByteArray {
    require(file.canonicalFile == file.absoluteFile && file.isFile)
    return FileInputStream(file).use { input ->
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(4096)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (count == 0 || output.size() + count > 65536) throw IOException()
            output.write(buffer, 0, count)
        }
        output.toByteArray()
    }
}

/** Only used under the native global owner lock. Scanner reads never invoke
 * AtomicFile recovery (which mutates .new/.bak files). */
internal class AudioPublicationDiskJournal(val directory: File) : AudioPublicationJournal {
    companion object { const val OWNER = "cmp-audio-publications-v1" }
    fun initialize(created: Boolean) {
        require(directory.canonicalFile == directory.absoluteFile && directory.isDirectory)
        val owner = File(directory, "owner.marker")
        if (created) atomic(owner, OWNER.toByteArray()) else {
            if (owner.exists() || File(owner.path + ".bak").exists()) AtomicFile(owner).openRead().close()
            else {
                // No committed owner and no phase files means initialization
                // never authorized a provider effect. Recover only this case.
                require(directory.listFiles()!!.all { it.name in setOf("owner.lock", "owner.marker.new") })
                val temporary = File(owner.path + ".new")
                if (temporary.exists()) require(temporary.canonicalFile == temporary.absoluteFile && temporary.length() <= 65536)
                AtomicFile(owner).delete()
                atomic(owner, OWNER.toByteArray())
            }
        }
        require(String(readAudioPublicationFile(owner), Charsets.UTF_8) == OWNER)
    }
    private fun atomic(file: File, bytes: ByteArray) {
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try { stream.write(bytes); stream.fd.sync(); atomic.finishWrite(stream) }
        catch (error: Exception) { atomic.failWrite(stream); throw error }
        require(readAudioPublicationFile(file).contentEquals(bytes))
    }
    override fun all(): List<List<AudioPublicationRecord>> {
        require(String(readAudioPublicationFile(File(directory, "owner.marker")), Charsets.UTF_8) == OWNER)
        val files = directory.listFiles() ?: throw IOException()
        require(files.size <= 64 * 5 * 3 + 2)
        val bases = files.filter { it.name !in setOf("owner.lock", "owner.marker") }.map {
            val name = it.name.removeSuffix(".bak").removeSuffix(".new")
            require(name.matches(Regex("[0-9a-f]{64}-[0-9a-f]{64}\\.(intent|creating|document|ready)")) ||
                name.matches(Regex("q-[0-9a-f]{64}\\.document")))
            name
        }.toSet()
        val groups = bases.mapNotNull { name ->
            val file = File(directory, name)
            if (!file.exists() && !File(file.path + ".bak").exists()) {
                // A first phase write died before its atomic commit. No later
                // provider effect was authorized by this uncommitted phase.
                require(File(file.path + ".new").length() <= 65536)
                AtomicFile(file).delete()
                return@mapNotNull null
            }
            // A previous process may have died inside an AtomicFile write.
            AtomicFile(file).openRead().close()
            val record = AudioPublicationCodec.decode(readAudioPublicationFile(file))
            if (name.startsWith("q-")) require(record.phase == AudioPublicationPhase.DOCUMENT && name == index(record))
            else require(name == name(record))
            record
        }.groupBy { it.binding.operation }.values.map { group ->
            group.groupBy { it.phase }.values.map { duplicates ->
                require(duplicates.all { it == duplicates.first() }); duplicates.first()
            }.sortedBy { it.phase.ordinal }.also { records ->
                require(records.all { it.binding == records.first().binding })
                require(records.any { it.phase == AudioPublicationPhase.INTENT } || records.any { it.phase == AudioPublicationPhase.READY })
                val doc = records.firstOrNull { it.phase == AudioPublicationPhase.DOCUMENT }
                val ready = records.firstOrNull { it.phase == AudioPublicationPhase.READY }
                if (doc != null && ready != null) require(doc.uri == ready.uri && doc.owned == ready.owned)
            }
        }
        require(groups.size <= 64)
        return groups
    }
    private fun name(record: AudioPublicationRecord) = "${record.binding.operation}.${record.phase.name.lowercase(java.util.Locale.ROOT)}"
    private fun index(record: AudioPublicationRecord): String {
        val uri = Uri.parse(record.uri ?: error("missing_uri"))
        return AudioPublicationVisibility.indexName(uri.authority ?: error("missing_authority"),DocumentsContract.getDocumentId(uri))
    }
    override fun save(record: AudioPublicationRecord) {
        if (record.phase == AudioPublicationPhase.DOCUMENT) {
            val index = File(directory,index(record))
            if (index.exists()) require(AudioPublicationCodec.decode(readAudioPublicationFile(index)) == record)
            else atomic(index,AudioPublicationCodec.encode(record))
        }
        val file = File(directory, name(record))
        if (file.exists()) {
            val old = AudioPublicationCodec.decode(readAudioPublicationFile(file))
            if (old == record) return
            require(record.phase == AudioPublicationPhase.INTENT && old.binding.samePublication(record.binding))
            require(all().first { it.first().binding.operation == record.binding.operation }.size == 1)
        }
        atomic(file, AudioPublicationCodec.encode(record))
    }
    override fun retire(binding: AudioPublicationBinding) {
        val records = all().firstOrNull { it.first().binding.operation == binding.operation } ?: emptyList()
        val document = records.firstOrNull { it.phase == AudioPublicationPhase.DOCUMENT }
        // Readers allow a verified file as soon as intent is gone. Never remove
        // READY first: a crash during acknowledgement must not hide valid audio.
        // For an unfinished diagnostic/no-effect operation keep INTENT until
        // its document index is gone, so a crash still leaves a valid group.
        val finished = records.any { it.phase == AudioPublicationPhase.READY }
        val phases = if (finished) listOf(AudioPublicationPhase.INTENT,AudioPublicationPhase.CREATING,AudioPublicationPhase.DOCUMENT)
            else listOf(AudioPublicationPhase.CREATING,AudioPublicationPhase.DOCUMENT)
        for (phase in phases) {
            val file = File(directory, "${binding.operation}.${phase.name.lowercase(java.util.Locale.ROOT)}")
            if (file.exists()) require(AudioPublicationCodec.decode(readAudioPublicationFile(file)).binding == binding)
            AtomicFile(file).delete()
            require(listOf(file, File(file.path + ".bak"), File(file.path + ".new")).none { it.exists() })
        }
        if (document != null) {
            require(document.binding == binding)
            val file = File(directory,index(document))
            AtomicFile(file).delete()
            require(listOf(file,File(file.path + ".bak"),File(file.path + ".new")).none { it.exists() })
        }
        if (!finished) {
            val intent = File(directory,"${binding.operation}.intent")
            if (intent.exists()) require(AudioPublicationCodec.decode(readAudioPublicationFile(intent)).binding == binding)
            AtomicFile(intent).delete()
            require(listOf(intent,File(intent.path + ".bak"),File(intent.path + ".new")).none { it.exists() })
        }
        val ready = File(directory,"${binding.operation}.ready")
        if (ready.exists()) require(AudioPublicationCodec.decode(readAudioPublicationFile(ready)).binding == binding)
        AtomicFile(ready).delete()
        require(listOf(ready,File(ready.path + ".bak"),File(ready.path + ".new")).none { it.exists() })
    }
}
