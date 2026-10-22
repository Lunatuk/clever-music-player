package dev.lunatuk.clever_music_player

import java.io.File

/** Fail closed for a managed operation name or document ID. No provider IO, no
 * journal writes/locks and no startup scan. Safe during concurrent phase writes. */
internal object AudioPublicationVisibility {
    private val managedName = Regex("cmp-([0-9a-f]{64}-[0-9a-f]{64})\\.(mp3|m4a|flac)")
    fun indexName(authority: String, documentId: String): String {
        require(!authority.contains('\u0000') && !documentId.contains('\u0000'))
        val digest = java.security.MessageDigest.getInstance("SHA-256")
            .digest((authority + '\u0000' + documentId).toByteArray(Charsets.UTF_8))
        val digits = "0123456789abcdef"
        val hex = buildString(64) { for (byte in digest) { val value = byte.toInt() and 255; append(digits[value ushr 4]); append(digits[value and 15]) } }
        return "q-$hex.document"
    }
    fun hidden(directory: File, authority: String?, displayName: String?, documentId: String? = null): Boolean {
        // The ID index also protects a pending document renamed by the user or
        // provider. It does not guess a path from an opaque document ID.
        if (authority != null && documentId != null && directory.exists()) {
            val index = File(directory,indexName(authority,documentId))
            if (listOf("", ".new", ".bak").any { File(index.path + it).exists() }) {
                return try {
                    require(String(readAudioPublicationFile(File(directory,"owner.marker")),Charsets.UTF_8) == AudioPublicationDiskJournal.OWNER)
                    val pending = AudioPublicationCodec.decode(readAudioPublicationFile(index))
                    require(pending.phase == AudioPublicationPhase.DOCUMENT)
                    if (pending.binding.probe) true else {
                        val ready = AudioPublicationCodec.decode(readAudioPublicationFile(File(directory,"${pending.binding.operation}.ready")))
                        require(ready.phase == AudioPublicationPhase.READY && ready.binding == pending.binding && ready.uri == pending.uri)
                        false
                    }
                } catch (_: Exception) { true }
            }
        }
        val match = displayName?.let { managedName.matchEntire(it) } ?: return false
        if (!directory.exists()) return false
        val stem = match.groupValues[1]
        fun file(phase: String) = File(directory, "$stem.$phase")
        val phases = listOf("intent", "creating", "document", "ready")
        if (phases.none { phase -> listOf("", ".new", ".bak").any { File(directory, "$stem.$phase$it").exists() } }) return false
        return try {
            require(String(readAudioPublicationFile(File(directory, "owner.marker")), Charsets.UTF_8) == AudioPublicationDiskJournal.OWNER)
            val base = if (file("intent").exists()) file("intent") else file("ready")
            val first = AudioPublicationCodec.decode(readAudioPublicationFile(base))
            require(first.binding.operation == stem && first.binding.name == displayName)
            if (java.net.URI(first.binding.tree).rawAuthority != authority) return false
            if (first.binding.probe) return true // even a completed test is never music
            if (!file("ready").exists()) return true
            val ready = AudioPublicationCodec.decode(readAudioPublicationFile(file("ready")))
            require(ready.phase == AudioPublicationPhase.READY && ready.binding == first.binding)
            false
        } catch (_: Exception) { true }
    }
}
