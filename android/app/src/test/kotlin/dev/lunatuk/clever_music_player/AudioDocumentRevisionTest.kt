package dev.lunatuk.clever_music_player

import org.junit.Assert.*
import org.junit.Test

class AudioDocumentRevisionTest {
    private val authority = "com.android.externalstorage.documents"
    private fun valid() = AudioDocumentRevision.create(authority,
        "primary:Музыка/song.m4a", "song.m4a", 100L, 1000L, true)!!

    @Test fun localCompleteDocumentHasStableIdentityAndVersionedMessage() {
        val revision = valid()
        assertEquals("primary:Музыка/song.m4a", revision.message()["documentId"])
        assertEquals(1, revision.message()["version"])
        assertEquals(100L, revision.message()["size"])
    }

    @Test fun unknownProvidersAndPartialVirtualDocumentsCannotUseCache() {
        assertNull(AudioDocumentRevision.create("cloud.documents", "id", "song", 100, 1000, true))
        assertNull(AudioDocumentRevision.create(authority, "id", "song", 100, 1000, false))
    }

    @Test fun absentNonpositiveOrUnboundedStampsCannotUseCache() {
        for (size in listOf(null, 0L, -1L, 9007199254740992L)) {
            assertNull(AudioDocumentRevision.create(authority, "id", "song", size, 1000, true))
        }
        for (modified in listOf(null, 0L, -1L, 8640000000000001L)) {
            assertNull(AudioDocumentRevision.create(authority, "id", "song", 100, modified, true))
        }
    }

    @Test fun missingOrOversizedIdentityCannotUseCache() {
        for (id in listOf(null, "", "x".repeat(4097))) {
            assertNull(AudioDocumentRevision.create(authority, id, "song", 100, 1000, true))
        }
        assertNull(AudioDocumentRevision.create(authority, "id", "", 100, 1000, true))
    }

    @Test fun replacementRenameOrMutationDuringReadCannotPublishCache() {
        val before = valid()
        for (after in listOf(null, before.copy(size = 101), before.copy(modifiedMs = 1001),
            before.copy(name = "renamed"), before.copy(documentId = "another"))) {
            assertNull(AudioDocumentRevision.confirm(before, after, true))
        }
        assertEquals(before, AudioDocumentRevision.confirm(before, before.copy(), true))
    }

    @Test fun incompleteReadOrMissingInitialStampCannotPublishCache() {
        assertNull(AudioDocumentRevision.confirm(valid(), valid(), false))
        assertNull(AudioDocumentRevision.confirm(null, valid(), true))
    }
}
