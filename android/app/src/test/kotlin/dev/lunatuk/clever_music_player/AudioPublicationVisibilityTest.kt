package dev.lunatuk.clever_music_player

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files

class AudioPublicationVisibilityTest {
    private val b = AudioPublicationBinding("a".repeat(64),"b".repeat(64),"content://music/tree/root","intent",3,
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","mp3","c".repeat(64))
    private fun fixture(action: (File) -> Unit) {
        val root = Files.createTempDirectory("cmp_visibility_").toFile().canonicalFile
        try {
            File(root,"owner.marker").writeText(AudioPublicationDiskJournal.OWNER)
            action(root)
        } finally {
            // Exclusively created, flat test directory; never recurse through links.
            for (file in root.listFiles() ?: emptyArray()) { require(file.parentFile == root); check(file.delete()) }
            check(root.delete())
        }
    }
    private fun save(root: File, record: AudioPublicationRecord) =
        File(root,"${record.binding.operation}.${record.phase.name.lowercase()}").writeBytes(AudioPublicationCodec.encode(record))
    private fun hidden(root: File, name: String = b.name, authority: String = "music") = AudioPublicationVisibility.hidden(root,authority,name)
    @Test fun ordinaryAndLegacyManagedFilesAreUnaffectedWithoutARecordedOperation() = fixture { root ->
        assertFalse(hidden(root)); assertFalse(hidden(root,"normal.mp3"))
    }
    @Test fun intentHidesExactManagedNameAcrossDifferentTreeGrantsButNotAnotherProvider() = fixture { root ->
        save(root,AudioPublicationRecord(b,AudioPublicationPhase.INTENT))
        assertTrue(hidden(root)); assertFalse(hidden(root,authority = "other"))
        assertFalse(hidden(root,"normal.mp3")); assertFalse(hidden(root,b.name.replace("b","d")))
    }
    @Test fun creatingAndPartiallyWrittenDocumentsStayHidden() = fixture { root ->
        save(root,AudioPublicationRecord(b,AudioPublicationPhase.INTENT))
        save(root,AudioPublicationRecord(b,AudioPublicationPhase.CREATING))
        assertTrue(hidden(root))
        save(root,AudioPublicationRecord(b,AudioPublicationPhase.DOCUMENT,"content://music/tree/root/document/x",true))
        assertTrue(hidden(root))
    }
    @Test fun readyAllowsMusicAndAcknowledgementCannotHideItAgain() = fixture { root ->
        save(root,AudioPublicationRecord(b,AudioPublicationPhase.INTENT))
        val ready = AudioPublicationRecord(b,AudioPublicationPhase.READY,"content://music/tree/root/document/x",true)
        save(root,ready); assertFalse(hidden(root))
        check(File(root,"${b.operation}.intent").delete())
        assertFalse(hidden(root))
        check(File(root,"${b.operation}.ready").delete())
        assertFalse(hidden(root))
    }
    @Test fun evenAReadyDiagnosticProbeNeverEntersTheMusicLibrary() = fixture { root ->
        val payload = AudioPublicationBinding.probeBytes(b.id)
        val hash = StreamingContentFingerprint.read(ByteArrayInputStream(payload),4096) { false }.digest
        val probe = b.copy(intent = "cmp-audio-publication-probe-v1",size = 4096,digest = hash,probe = true)
        save(root,AudioPublicationRecord(probe,AudioPublicationPhase.READY,"content://music/tree/root/document/x",true))
        assertTrue(hidden(root))
    }
    @Test fun corruptOrUncommittedMarkersFailClosedWithoutReaderMutations() = fixture { root ->
        val partial = File(root,"${b.operation}.intent.new")
        partial.writeText("partial")
        assertTrue(hidden(root)); assertEquals("partial",partial.readText())
        save(root,AudioPublicationRecord(b,AudioPublicationPhase.INTENT))
        File(root,"${b.operation}.ready").writeText("broken")
        assertTrue(hidden(root)); assertEquals("partial",partial.readText())
        File(root,"owner.marker").writeText("foreign")
        assertTrue(hidden(root))
    }
    @Test fun forgedReadyBindingDoesNotMakePartialAudioVisible() = fixture { root ->
        save(root,AudioPublicationRecord(b,AudioPublicationPhase.INTENT))
        save(root,AudioPublicationRecord(b.copy(intent = "other"),AudioPublicationPhase.READY,"content://music/tree/root/document/x",true))
        assertTrue(hidden(root))
    }
    @Test fun walkerChecksVisibilityAtTheLeafAndDoesNotRetainAScanStartSnapshot() {
        val entries = listOf(TreeDocument("hidden","audio/mpeg","one.mp3"),TreeDocument("shown","audio/mpeg","two.mp3"))
        var current = 0; var hiddenNow = false
        val walker = DocumentTreeWalker("root", { object : TreeDirectoryCursor {
            override fun next(): TreeDocument? = entries.getOrNull(current++)
            override fun close() {}
        } }, includeAudio = { !(hiddenNow && it.id == "hidden") })
        hiddenNow = true // publication starts after the folder session opens
        walker.use { assertEquals(listOf("shown"),it.nextPage().ids) }
    }
    @Test fun documentIdQuarantineSurvivesRenameUntilMatchingReadyProof() = fixture { root ->
        val id = "opaque/with spaces:+\u044f"
        val document = AudioPublicationRecord(b,AudioPublicationPhase.DOCUMENT,"content://music/tree/root/document/x",true)
        File(root,AudioPublicationVisibility.indexName("music",id)).writeBytes(AudioPublicationCodec.encode(document))
        fun renamed(documentId: String = id) = AudioPublicationVisibility.hidden(root,"music","renamed.mp3",documentId)
        assertTrue(renamed()); assertFalse(renamed("another"))
        save(root,document.copy(phase = AudioPublicationPhase.READY,uri = "content://music/tree/root/document/other"))
        assertTrue(renamed())
        save(root,document.copy(phase = AudioPublicationPhase.READY))
        assertFalse(renamed())
        File(root,"owner.marker").writeText("foreign")
        assertTrue(renamed())
    }
    @Test fun corruptOrUncommittedIdIndexHidesRenamedDocumentWithoutChangingFiles() = fixture { root ->
        val index = File(root,AudioPublicationVisibility.indexName("music","x"))
        val temporary = File(index.path + ".new"); temporary.writeText("partial")
        assertTrue(AudioPublicationVisibility.hidden(root,"music","renamed.m4a","x"))
        assertEquals("partial",temporary.readText()); assertFalse(index.exists())
        index.writeText("broken")
        assertTrue(AudioPublicationVisibility.hidden(root,"music","renamed.m4a","x"))
        assertEquals("broken",index.readText())
    }
    @Test fun walkerSkipsKnownEmptyDocumentsButAllowsUnknownSizeAndNonemptyAudio() {
        val entries = listOf(TreeDocument("empty","audio/mpeg","one.mp3",0),
            TreeDocument("unknown","audio/mpeg","two.mp3"),TreeDocument("nonempty","audio/mpeg","three.mp3",3))
        var current = 0
        val walker = DocumentTreeWalker("root", { object : TreeDirectoryCursor {
            override fun next(): TreeDocument? = entries.getOrNull(current++)
            override fun close() {}
        } })
        walker.use { assertEquals(listOf("unknown","nonempty"),it.nextPage().ids) }
    }
}
