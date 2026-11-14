package dev.lunatuk.clever_music_player

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Test

class AudioSourceCommentsTest {
    private val url = "https://music.yandex.ru/album/12/track/34"
    private fun word(value: Long, little: Boolean = false) = ByteBuffer.allocate(4)
        .order(if (little) ByteOrder.LITTLE_ENDIAN else ByteOrder.BIG_ENDIAN).putInt(value.toInt()).array()
    private fun sync(value: Int) = byteArrayOf((value shr 21 and 127).toByte(),
        (value shr 14 and 127).toByte(), (value shr 7 and 127).toByte(), (value and 127).toByte())
    private fun ascii(value: String) = value.toByteArray(Charsets.ISO_8859_1)
    private fun frame(key: String, bytes: ByteArray, version: Int = 4, flags: Int = 0): ByteArray =
        ascii(key) + (if (version == 2) word(bytes.size.toLong()).copyOfRange(1, 4)
        else if (version == 4) sync(bytes.size) else word(bytes.size.toLong())) +
            (if (version == 2) byteArrayOf() else byteArrayOf(0, flags.toByte())) + bytes
    private fun mp3(frames: ByteArray, version: Int = 4, flags: Int = 0) =
        ascii("ID3") + byteArrayOf(version.toByte(), 0, flags.toByte()) + sync(frames.size) + frames
    private fun comm(value: String = url) = byteArrayOf(3) + ascii("engSource") + byteArrayOf(0) + value.toByteArray(Charsets.UTF_8)
    private fun parse(data: ByteArray) = AudioSourceComments.Parser(data.size.toLong()) { p, n ->
        data.copyOfRange(p.toInt(), p.toInt() + n)
    }.parse()
    private fun atom(key: String, bytes: ByteArray, wide: Boolean = false, zero: Boolean = false): ByteArray =
        word(if (zero) 0 else if (wide) 1 else bytes.size + 8L) + ascii(key) +
            (if (wide) ByteBuffer.allocate(8).putLong(bytes.size + 16L).array() else byteArrayOf()) + bytes
    private fun mp4(vararg comments: ByteArray) = atom("ftyp", ascii("M4A ") + word(0)) +
        atom("moov", atom("udta", atom("meta", word(0) + atom("ilst", comments.fold(byteArrayOf()) { a, b -> a + b }))))
    private fun cmt(value: String = url, type: Long = 1) = atom("\u00a9cmt", atom("data", word(type) + word(0) +
        value.toByteArray(if (type == 2L) Charsets.UTF_16BE else Charsets.UTF_8)))
    private fun block(type: Int, bytes: ByteArray) = byteArrayOf(type.toByte()) + word(bytes.size.toLong()).copyOfRange(1, 4) + bytes
    private fun flac(vararg entries: String): ByteArray {
        val vorbis = word(3, true) + ascii("CMP") + word(entries.size.toLong(), true) +
            entries.fold(byteArrayOf()) { a, value -> val bytes = value.toByteArray(Charsets.UTF_8); a + word(bytes.size.toLong(), true) + bytes }
        return ascii("fLaC") + block(0, ByteArray(34)) + block(132, vorbis)
    }

    @Test fun commentEncodingsAndFrameVersions() {
        for (version in 2..4) for (encoding in 0..3) {
            val charset = when (encoding) { 0 -> Charsets.ISO_8859_1; 1 -> Charsets.UTF_16; 2 -> Charsets.UTF_16BE; else -> Charsets.UTF_8 }
            val payload = byteArrayOf(encoding.toByte()) + ascii("eng") + "Source".toByteArray(charset) +
                ByteArray(if (encoding in 1..2) 2 else 1) + url.toByteArray(charset)
            assertEquals("v=$version encoding=$encoding", listOf(url), parse(mp3(frame(if (version == 2) "COM" else "COMM", payload, version), version)))
        }
    }
    @Test fun utf16LittleEndianMayInheritDescriptionBom() {
        val data = byteArrayOf(1) + ascii("eng") + byteArrayOf(-1, -2) + "Источник".toByteArray(Charsets.UTF_16LE) +
            byteArrayOf(0, 0) + url.toByteArray(Charsets.UTF_16LE)
        assertEquals(listOf(url), parse(mp3(frame("COMM", data))))
    }
    @Test fun collectsEveryCommentAndOnlyCommentUserText() {
        val frames = frame("COMM", comm()) + frame("COMM", comm("https://music.yandex.ru/track/99")) +
            frame("TXXX", byteArrayOf(3) + ascii("comment\u0000$url")) +
            frame("TXXX", byteArrayOf(3) + ascii("title\u0000not-a-source"))
        assertEquals(listOf(url, "https://music.yandex.ru/track/99", url), parse(mp3(frames)))
    }
    @Test fun extendedHeaders() {
        for (version in 3..4) {
            val extended = if (version == 3) word(6) + ByteArray(6) else sync(6) + byteArrayOf(1, 0)
            assertEquals(listOf(url), parse(mp3(extended + frame("COMM", comm(), version), version, 64)))
        }
    }
    @Test fun v4FrameUnsynchronisationGroupingAndLengthIndicator() {
        val payload = byteArrayOf(1) + ascii("eng") + byteArrayOf(-1, -2) + "Source".toByteArray(Charsets.UTF_16LE) +
            byteArrayOf(0, 0) + byteArrayOf(-1, -2) + url.toByteArray(Charsets.UTF_16LE)
        val stuffed = payload.fold(byteArrayOf()) { a, b -> a + b + (if (b == (-1).toByte()) byteArrayOf(0) else byteArrayOf()) }
        assertEquals(listOf(url), parse(mp3(frame("COMM", byteArrayOf(7) + sync(payload.size) + stuffed, flags = 67))))
        assertEquals(listOf(url), parse(mp3(frame("COMM", stuffed), flags = 128)))
    }
    @Test fun unsupportedTransformsReturnUnknown() {
        assertNull(parse(mp3(frame("COMM", comm(), 3), 3, 128)))
        for (flag in listOf(4, 8, 128)) assertNull(parse(mp3(frame("COMM", comm(), flags = flag))))
    }
    @Test fun supportsV1AndAppendedV4WithoutDiscardingConflicts() {
        val v1url = "http://music.yandex.ru/track/1"
        val v1 = ascii("TAG") + ByteArray(94) + ascii(v1url).copyOf(30) + byteArrayOf(0)
        val frames = frame("COMM", comm())
        val header = mp3(frames, flags = 16)
        val footer = ascii("3DI") + header.copyOfRange(3, 10)
        val audio = byteArrayOf(-1, -5) + ByteArray(200)
        assertEquals(listOf(v1url + "\u0000".repeat(30 - v1url.length), url), parse(audio + header + footer + v1))
    }
    @Test fun v4HeaderFooterAgreement() {
        val data = mp3(frame("COMM", comm()), flags = 16)
        assertEquals(listOf(url), parse(data + ascii("3DI") + data.copyOfRange(3, 10)))
        assertNull(parse(data + ByteArray(10)))
    }
    @Test fun malformedAndOversizedCommentsNeverProducePartialResults() {
        assertNull(parse(mp3(frame("COMM", comm()) + ascii("BROK"))))
        assertNull(parse(mp3(frame("COMM", comm()) + frame("COMM", byteArrayOf(3, 1)))))
        assertNull(parse(mp3(frame("COMM", comm("a".repeat(4097))))))
        assertNull(parse(mp3(frame("COMM", byteArrayOf(3) + ascii("eng\u0000") + byteArrayOf(-61, 40)))))
        val frames = (0..32).fold(byteArrayOf()) { a, _ -> a + frame("COMM", comm()) }
        assertNull(parse(mp3(frames)))
    }
    @Test fun flacCollectsCaseInsensitiveCommentAndDescriptionEntries() {
        assertEquals(listOf(url, "https://music.yandex.ru/track/99"), parse(flac("TITLE=$url", "comment=$url", "DESCRIPTION=https://music.yandex.ru/track/99")))
        assertEquals(emptyList<String>(), parse(flac("TITLE=$url")))
    }
    @Test fun malformedVorbisLengthsAndUtf8AreUnknown() {
        val valid = flac("COMMENT=$url")
        assertNull(parse(valid.copyOf(valid.size - 1)))
        val invalid = valid.copyOf().also { it[it.lastIndex] = -1 }
        assertNull(parse(invalid))
        val body = word(0, true) + word(1, true) + word(0xffffffffL, true)
        assertNull(parse(ascii("fLaC") + block(132, body)))
    }
    @Test fun mp4PreservesMultipleCommentsAndBothTextTypes() {
        assertEquals(listOf(url, "https://music.yandex.ru/track/99"), parse(mp4(cmt(), cmt("https://music.yandex.ru/track/99", 2))))
        assertEquals(listOf(url), parse(mp4(cmt("\uFEFF$url", 2))))
        assertEquals(emptyList<String>(), parse(mp4(atom("\u00a9nam", atom("data", word(1) + word(0) + ascii(url))))))
    }
    @Test fun mp4ExtendedAndZeroSizedAtoms() {
        val tags = atom("udta", atom("meta", word(0) + atom("ilst", cmt())))
        assertEquals(listOf(url), parse(atom("moov", tags, wide = true)))
        assertEquals(listOf(url), parse(atom("moov", tags, zero = true)))
    }
    @Test fun mp4RejectsTruncatedExtendedOrUnknownDataAndOverflowingLengths() {
        assertNull(parse(mp4(cmt(type = 13))))
        assertNull(parse(mp4(cmt()).let { it.copyOf(it.size - 1) }))
        assertNull(parse(word(1) + ascii("moov") + ByteBuffer.allocate(8).putLong(Long.MAX_VALUE).array()))
        assertNull(parse(word(4) + ascii("moov")))
    }
    @Test fun declaredDescriptorSubrangeIsEnforcedAndPositionIsPreserved() {
        val file = File.createTempFile("cmp-source-comments", ".bin")
        try {
            val music = mp4(cmt())
            file.writeBytes(ByteArray(37) + music + mp4(cmt("https://music.yandex.ru/track/99")))
            RandomAccessFile(file, "r").use {
                it.seek(3)
                assertEquals(listOf(url), AudioSourceComments.read(it.channel, 37, music.size.toLong()))
                assertEquals(3L, it.filePointer)
                assertNull(AudioSourceComments.read(it.channel, -1))
                assertNull(AudioSourceComments.read(it.channel, 37, file.length()))
                assertTrue(it.channel.isOpen)
            }
        } finally { file.delete() }
    }
    @Test fun largeArtAndAudioAreSkippedRatherThanRead() {
        val picture = 4_000_000L
        val header = ascii("ID3") + byteArrayOf(4, 0, 0) + sync((10 + picture + frame("COMM", comm()).size).toInt())
        val image = ascii("APIC") + sync(picture.toInt()) + byteArrayOf(0, 0)
        val comment = frame("COMM", comm())
        val offset = 10L + image.size + picture
        var totalRead = 0
        val size = offset + comment.size + 100_000_000
        val value = AudioSourceComments.Parser(size) { p, n ->
            totalRead += n
            require(!(p >= 20 && p < offset))
            ByteArray(n) { i -> val pos = p + i; when {
                pos < header.size -> header[pos.toInt()]
                pos < 20 -> image[(pos - 10).toInt()]
                pos in offset until offset + comment.size -> comment[(pos - offset).toInt()]
                else -> 0
            } }
        }.parse()
        assertEquals(listOf(url), value)
        assertTrue(totalRead < 512)
    }
    @Test fun parserWorkAndAllocationAreBounded() {
        val empty = atom("free", byteArrayOf())
        val many = ByteArray(9001 * empty.size)
        repeat(9001) { empty.copyInto(many, it * empty.size) }
        assertNull(parse(many))
        val huge = 4_294_967_300L
        val box = word(1) + ascii("data") + ByteBuffer.allocate(8).putLong(huge + 16).array()
        // A size that would wrap to a small positive Int must still be rejected.
        val header = atom("ftyp", ascii("M4A "))
        assertNull(parse(header + box))
    }
    @Test fun unknownAndRandomTruncatedInputsDoNotEscape() {
        assertNull(parse(ascii("RIFF") + ByteArray(32)))
        val random = java.util.Random(34)
        repeat(1000) { val data = ByteArray(random.nextInt(256)); random.nextBytes(data); parse(data) }
    }
    @Test fun readsEncodedMp3M4aAndFlacSharedWithTheDesktopReader() {
        for (extension in listOf("mp3", "m4a", "flac")) {
            val bytes = javaClass.getResourceAsStream("/linked.$extension")!!.use { it.readBytes() }
            assertEquals(extension, listOf(url), parse(bytes)?.map { it.trim('\u0000') })
        }
    }
    private fun sparse(size: Long, regions: Map<Long, ByteArray>): List<String>? =
        AudioSourceComments.Parser(size) { position, count -> ByteArray(count) { i ->
            val p = position + i
            val entry = regions.entries.firstOrNull { p >= it.key && p - it.key < it.value.size }
                ?: error("audio_or_cover_was_read")
            entry.value[(p - entry.key).toInt()]
        } }.parse()
    @Test fun largeM4aAudioAndCoverAreSkipped() {
        val ftyp = atom("ftyp", ascii("M4A ") + word(0))
        val audioSize = 100_000_000L
        val pictureSize = 4_000_000L
        val comment = cmt()
        val ilstSize = 8 + 8 + pictureSize + comment.size
        val metaSize = 12 + ilstSize
        val udtaSize = 8 + metaSize
        val moovSize = 8 + udtaSize
        val first = ftyp + word(audioSize + 8) + ascii("mdat")
        val moov = word(moovSize) + ascii("moov") + word(udtaSize) + ascii("udta") +
            word(metaSize) + ascii("meta") + word(0) + word(ilstSize) + ascii("ilst") +
            word(pictureSize + 8) + ascii("covr")
        val moovOffset = first.size + audioSize
        val commentOffset = moovOffset + moov.size + pictureSize
        assertEquals(listOf(url), sparse(commentOffset + comment.size,
            mapOf(0L to first, moovOffset to moov, commentOffset to comment)))
    }
    @Test fun largeFlacPictureIsSkipped() {
        val pictureSize = 5_000_000L
        val prefix = ascii("fLaC") + block(0, ByteArray(34)) + byteArrayOf(6) + word(pictureSize).copyOfRange(1, 4)
        val comments = flac("COMMENT=$url").copyOfRange(42, flac("COMMENT=$url").size)
        val position = prefix.size + pictureSize
        assertEquals(listOf(url), sparse(position + comments.size, mapOf(0L to prefix, position to comments)))
    }
    @Test fun partialProviderReadsAreUnknown() {
        assertNull(AudioSourceComments.Parser(1000) { _, _ -> throw java.io.IOException("provider failed") }.parse())
        assertNull(AudioSourceComments.Parser(1000) { _, n -> ByteArray(maxOf(0, n - 1)) }.parse())
    }
}
