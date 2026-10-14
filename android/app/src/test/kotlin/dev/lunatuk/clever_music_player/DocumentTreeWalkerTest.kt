package dev.lunatuk.clever_music_player

import org.junit.Assert.*
import org.junit.Test

class DocumentTreeWalkerTest {
    private class Cursor(val rows: List<TreeDocument>) : TreeDirectoryCursor {
        var index = 0
        var closes = 0
        var failure: Exception? = null
        override fun next(): TreeDocument? {
            failure?.let { throw it }
            return rows.getOrNull(index++)
        }
        override fun close() { closes++ }
    }
    private fun song(id: String) = TreeDocument(id, "audio/mpeg", "$id.mp3")
    private fun dir(id: String) = TreeDocument(id, "vnd.android.document/directory", id)

    @Test fun pagesMoreThan64AndNestedFilesWithoutRepeatingCycles() {
        val root = Cursor((1..150).map { song("s$it") } + listOf(dir("child"), dir("child")))
        val child = Cursor(listOf(dir("root"), song("nested"), song("s1")))
        val opened = mutableListOf<String>()
        val walker = DocumentTreeWalker("root", { id -> opened.add(id); if (id == "root") root else child })
        val result = mutableListOf<String>()
        var done = false
        while (!done) {
            val page = walker.nextPage()
            assertTrue(page.ids.size <= 64)
            result.addAll(page.ids)
            done = page.done
        }
        assertEquals(151, result.size)
        assertEquals(result.size, result.toSet().size)
        assertEquals(listOf("root", "child"), opened)
        walker.close()
        assertEquals(1, root.closes)
        assertEquals(1, child.closes)
    }

    @Test fun filtersNonAudioAndAcceptsKnownExtensionWithUnknownMime() {
        val cursor = Cursor(listOf(TreeDocument("photo", "image/jpeg", "cover.jpg"),
            TreeDocument("unknown", null, "TRACK.FLAC"), song("music")))
        val walker = DocumentTreeWalker("root", { cursor })
        assertEquals(listOf("unknown", "music"), walker.nextPage().ids)
        walker.close()
    }

    @Test fun emptyDirectoriesYieldBoundedWorkPages() {
        val roots = (1..1000).map { dir("d$it") }
        val walker = DocumentTreeWalker("root", { if (it == "root") Cursor(roots) else Cursor(emptyList()) }, pageWork = 10)
        val page = walker.nextPage()
        assertFalse(page.done)
        assertEquals(10, page.visited)
        walker.close()
    }

    @Test fun closeBetweenPagesReleasesOpenCursorExactlyOnce() {
        val cursor = Cursor((1..100).map { song("s$it") })
        val walker = DocumentTreeWalker("root", { cursor })
        assertEquals(64, walker.nextPage().ids.size)
        walker.close()
        walker.close()
        assertEquals(1, cursor.closes)
        assertThrows(IllegalStateException::class.java) { walker.nextPage() }
    }

    @Test fun cancellationClosesCursorAndDoesNotEnumerateNextDirectory() {
        var cancel = false
        val cursor = Cursor((1..100).map { song("s$it") } + dir("child"))
        var opens = 0
        val walker = DocumentTreeWalker("root", { opens++; cursor }, cancelled = { cancel })
        walker.nextPage()
        cancel = true
        assertThrows(IllegalStateException::class.java) { walker.nextPage() }
        assertEquals(1, cursor.closes)
        assertEquals(1, opens)
    }

    @Test fun providerFailureAndTraversalLimitBothCloseCursor() {
        val cursor = Cursor((1..100).map { song("s$it") })
        val walker = DocumentTreeWalker("root", { cursor }, maxNodes = 5)
        assertThrows(IllegalStateException::class.java) { walker.nextPage() }
        assertEquals(1, cursor.closes)
        val broken = Cursor(emptyList()).apply { failure = IllegalArgumentException("provider") }
        val other = DocumentTreeWalker("root", { broken })
        assertThrows(IllegalArgumentException::class.java) { other.nextPage() }
        assertEquals(1, broken.closes)
    }
}
