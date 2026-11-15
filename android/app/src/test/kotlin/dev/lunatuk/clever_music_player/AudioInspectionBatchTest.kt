package dev.lunatuk.clever_music_player

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class AudioInspectionBatchTest {
    private fun requests(n: Int) = (0 until n).map { AudioInspectionRequest("song$it", false, null, null) }
    private fun ok() = mapOf<String, Any?>("failed" to false, "artwork" to 3)
    private fun frames(result: Map<String, Any?>) = result["results"] as List<*>

    @Test fun boundedBatchPreservesTheRequestedPrefixAndOrdering() {
        val result = AudioInspectionBatch.run(requests(8), { false }, { ok() }, { 0L })
        assertEquals(8, result["consumed"])
        assertEquals(false, result["cancelled"])
        assertEquals((0 until 8).map { "song$it" }, frames(result).map { (it as Map<*, *>)["source"] })
    }

    @Test fun timeBudgetYieldsACompletePrefixWithAgeMeasurements() {
        var now = 0L
        val result = AudioInspectionBatch.run(requests(8), { false }, { now += 120000000; ok() }, { now })
        assertEquals(2, result["consumed"])
        assertEquals(120000L, (frames(result)[0] as Map<*, *>)["ageUs"])
        assertEquals(0L, (frames(result)[1] as Map<*, *>)["ageUs"])
    }

    @Test fun oneSlowProviderCallStillMakesFiniteProgress() {
        var now = 0L
        val result = AudioInspectionBatch.run(requests(8), { false }, { now += 900000000; ok() }, { now })
        assertEquals(1, result["consumed"])
    }

    @Test fun cancellationBeforeStartDoesNotInspectAnything() {
        var calls = 0
        val result = AudioInspectionBatch.run(requests(3), { true }, { calls++; ok() })
        assertEquals(0, calls)
        assertEquals(0, result["consumed"])
        assertEquals(true, result["cancelled"])
    }

    @Test fun cancellationDuringAnItemDiscardsItsIncompleteProof() {
        var cancel = false
        var calls = 0
        val result = AudioInspectionBatch.run(requests(3), { cancel }, {
            if (++calls == 2) cancel = true
            ok()
        }, { 0L })
        assertEquals(1, result["consumed"])
        assertEquals(true, result["cancelled"])
    }

    @Test fun failedItemIsSanitizedAndDoesNotStopItsNeighbours() {
        val result = AudioInspectionBatch.run(requests(3), { false }, {
            if (it.source == "song1") throw SecurityException("private path and token")
            ok()
        }, { 0L })
        assertEquals(3, result["consumed"])
        assertEquals(true, (frames(result)[1] as Map<*, *>)["failed"])
        assertFalse(result.toString().contains("private path"))
    }

    @Test fun invalidBatchSizesAndDuplicateSourcesAreRejected() {
        for (items in listOf(requests(0), requests(9), listOf(requests(1)[0], requests(1)[0]))) {
            try { AudioInspectionBatch.run(items, { false }, { ok() }); fail("accepted invalid batch") }
            catch (_: IllegalArgumentException) {}
        }
    }

    private fun withCache(test: (File, File) -> Unit) {
        val temporary = Files.createTempDirectory("cmp-batch-").toFile().canonicalFile
        val cache = File(temporary, "cache").apply { mkdir() }
        try { test(temporary, cache) } finally {
            check(temporary.parentFile.canonicalFile == File(System.getProperty("java.io.tmpdir")).canonicalFile)
            check(temporary.name.startsWith("cmp-batch-"))
            temporary.deleteRecursively()
        }
    }

    @Test fun onlyNonemptyContentAddressedArtworkInsideTheCacheIsAttested() = withCache { _, root ->
        val hash = "a".repeat(64)
        val file = File(root, "$hash.webp").apply { writeBytes(byteArrayOf(1)) }
        val request = AudioInspectionRequest("song", true, file.path, hash)
        val probe = AudioArtworkProbe(root)
        assertEquals(1, probe.check(request))
        file.writeBytes(byteArrayOf())
        assertEquals(2, probe.check(request))
        file.delete()
        assertEquals(2, probe.check(request))
    }

    @Test fun privatePathEscapeAndInvalidHashRemainUnsupported() = withCache { temporary, root ->
        val hash = "b".repeat(64)
        val outside = File(temporary, "$hash.webp").apply { writeBytes(byteArrayOf(1)) }
        val probe = AudioArtworkProbe(root)
        assertEquals(0, probe.check(AudioInspectionRequest("song", true, outside.path, hash)))
        assertEquals(0, probe.check(AudioInspectionRequest("song", true, "$hash.webp", hash)))
        assertEquals(0, probe.check(AudioInspectionRequest("song", true, outside.path, "invalid")))
    }

    @Test fun knownAbsenceAndLegacyExtensionsHaveDistinctOutcomes() = withCache { _, root ->
        val hash = "c".repeat(64)
        val probe = AudioArtworkProbe(root)
        assertEquals(3, probe.check(AudioInspectionRequest("song", false, null, null)))
        val file = File(root, "$hash.jpeg").apply { writeBytes(byteArrayOf(1)) }
        assertEquals(1, probe.check(AudioInspectionRequest("song", true, file.path, hash)))
    }
}
