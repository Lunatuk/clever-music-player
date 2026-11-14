package dev.lunatuk.clever_music_player

import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.util.Locale

/** Read-only, bounded tag access. Pictures/audio are skipped with positional IO.
 * null means incomplete/unsupported: callers must preserve existing source links.
 * An empty list means a complete read found no source comments.
 * Formats: https://id3.org/id3v2.3.0, https://id3.org/id3v2.4.0-structure,
 * RFC 9639 (Vorbis comments), MP4 moov/udta/meta/ilst/©cmt/data.
 */
internal object AudioSourceComments {
    fun read(channel: FileChannel, offset: Long = 0, length: Long = -1): List<String>? = try {
        val available = channel.size()
        require(offset >= 0 && offset <= available && length >= -1)
        val size = if (length < 0) available - offset else length
        require(size in 1..(8L * 1024 * 1024 * 1024) && size <= available - offset)
        Parser(size) { position, count ->
            val buffer = ByteBuffer.allocate(count)
            while (buffer.hasRemaining()) {
                val n = channel.read(buffer, offset + position + buffer.position())
                if (n <= 0) throw IOException("incomplete_tags")
            }
            buffer.array()
        }.parse()
    } catch (_: Exception) { null }

    // Injectable positional reads also let JVM tests prove that large pictures
    // and audio payloads are never read. The parser owns no file/descriptors.
    internal class Parser(private val size: Long, private val input: (Long, Int) -> ByteArray) {
        private val comments = mutableListOf<String>()
        private var reads = 0
        private var bytes = 0
        private val deadline = System.nanoTime() + 2_000_000_000L

        private fun read(position: Long, count: Int, end: Long = size): ByteArray {
            require(position >= 0 && count >= 0 && end <= size && position <= end - count)
            require(++reads <= 8192 && count <= 16384 && bytes <= 1024 * 1024 - count)
            require(System.nanoTime() <= deadline)
            bytes += count
            return input(position, count).also { require(it.size == count) }
        }
        private fun number(data: ByteArray, start: Int = 0, count: Int = 4, little: Boolean = false): Long {
            var value = 0L
            for (i in 0 until count) value = (value shl 8) or
                (data[start + if (little) count - 1 - i else i].toLong() and 255)
            require(value >= 0)
            return value
        }
        private fun sync(data: ByteArray, start: Int = 0): Long {
            var value = 0L
            for (i in start until start + 4) {
                val byte = data[i].toInt() and 255
                require(byte < 128)
                value = (value shl 7) or byte.toLong()
            }
            return value
        }
        private fun text(data: ByteArray, charset: Charset): String = charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(data)).toString()
        private fun add(value: String) {
            require(comments.size < 32 && value.length <= 4096)
            comments.add(value)
        }
        private fun kind(data: ByteArray, offset: Int = 0, count: Int = 4) =
            String(data, offset, count, Charsets.ISO_8859_1)

        fun parse(): List<String>? = try {
            val head = read(0, minOf(size, 12).toInt())
            when {
                head.size >= 10 && kind(head, 0, 3) == "ID3" -> { id3(0); id3v1() }
                head.size >= 4 && kind(head) == "fLaC" -> flac()
                head.size >= 8 && kind(head, 4) in setOf("ftyp", "moov", "free", "wide", "mdat") -> boxes(0, size, "root")
                head.size >= 2 && head[0].toInt() and 255 == 255 &&
                    head[1].toInt() and 224 == 224 && head[1].toInt() and 6 != 0 -> id3v1()
                else -> error("unsupported_tags")
            }
            comments.toList()
        } catch (_: Exception) { null }

        private fun id3(start: Long) {
            val header = read(start, 10)
            val version = header[3].toInt() and 255
            val flags = header[5].toInt() and 255
            require(version in 2..4 && header[4].toInt() and 255 < 255)
            require(flags and (if (version == 2) 63 else if (version == 3) 31 else 15) == 0)
            // v2.2 compression and v2.3 whole-tag unsynchronisation require a
            // different byte address space. Leave the identity unknown safely.
            require(!(version == 2 && flags != 0) && !(version == 3 && flags and 128 != 0))
            val end = start + 10 + sync(header, 6)
            require(end <= size)
            var position = start + 10
            if (version >= 3 && flags and 64 != 0) {
                val extended = read(position, 4, end)
                val length = if (version == 4) sync(extended) else number(extended) + 4
                require(length >= if (version == 4) 6 else 10)
                require(length <= end - position)
                position += length
            }
            val frameHeader = if (version == 2) 6 else 10
            while (position < end) {
                val h = read(position, minOf(frameHeader.toLong(), end - position).toInt(), end)
                if (h.all { it == 0.toByte() }) break
                require(h.size == frameHeader)
                val key = kind(h, 0, if (version == 2) 3 else 4)
                require(key.all { it in 'A'..'Z' || it in '0'..'9' })
                val length = if (version == 2) number(h, 3, 3) else if (version == 4) sync(h, 4) else number(h, 4)
                position += frameHeader
                require(length <= end - position)
                if (key in setOf("COMM", "COM", "TXXX", "TXX")) {
                    require(length in 1..16384)
                    var payload = read(position, length.toInt(), end)
                    val format = if (version >= 3) h[9].toInt() and 255 else 0
                    require(format and (if (version == 4) 176 else 31) == 0)
                    require(format and (if (version == 4) 12 else 192) == 0)
                    if (version == 4 && (format and 2 != 0 || flags and 128 != 0)) {
                        val decoded = ArrayList<Byte>(payload.size)
                        var i = 0
                        while (i < payload.size) {
                            val byte = payload[i++]
                            decoded.add(byte)
                            if (byte == 255.toByte() && i < payload.size && payload[i] == 0.toByte()) i++
                        }
                        payload = decoded.toByteArray()
                    }
                    val prefix = (if (format and (if (version == 4) 64 else 32) != 0) 1 else 0) +
                        (if (version == 4 && format and 1 != 0) 4 else 0)
                    require(prefix < payload.size)
                    comment(payload.copyOfRange(prefix, payload.size), key == "COMM" || key == "COM")
                }
                position += length
            }
            if (version == 4 && flags and 16 != 0) {
                val footer = read(end, 10)
                require(kind(footer, 0, 3) == "3DI" && footer.copyOfRange(3, 10).contentEquals(header.copyOfRange(3, 10)))
            }
        }
        private fun comment(data: ByteArray, isComment: Boolean) {
            val encoding = data[0].toInt() and 255
            require(encoding in 0..3)
            val start = if (isComment) 4 else 1
            val width = if (encoding in 1..2) 2 else 1
            var split = start
            while (split + width <= data.size && !(data[split] == 0.toByte() &&
                (width == 1 || data[split + 1] == 0.toByte()))) split += width
            require(split + width <= data.size)
            val description = data.copyOfRange(start, split)
            val body = data.copyOfRange(split + width, data.size)
            val charset = when (encoding) {
                0 -> Charsets.ISO_8859_1
                3 -> Charsets.UTF_8
                2 -> Charsets.UTF_16BE
                else -> {
                    val marker = if (description.size >= 2) description else body
                    require(marker.size >= 2)
                    when {
                        marker[0] == 255.toByte() && marker[1] == 254.toByte() -> Charsets.UTF_16LE
                        marker[0] == 254.toByte() && marker[1] == 255.toByte() -> Charsets.UTF_16BE
                        else -> error("missing_bom")
                    }
                }
            }
            fun decode(bytes: ByteArray): String {
                val actual = if (encoding == 1 && bytes.size >= 2) when {
                    bytes[0] == 255.toByte() && bytes[1] == 254.toByte() -> Charsets.UTF_16LE
                    bytes[0] == 254.toByte() && bytes[1] == 255.toByte() -> Charsets.UTF_16BE
                    else -> charset
                } else charset
                return text(bytes, actual).removePrefix("\uFEFF")
            }
            if (isComment || decode(description).lowercase(Locale.ROOT) == "comment") add(decode(body))
        }
        private fun id3v1() {
            val tag = if (size >= 128) read(size - 128, 128) else null
            val hasTag = tag != null && kind(tag, 0, 3) == "TAG"
            if (hasTag) {
                val end = if (tag[125] == 0.toByte()) 125 else 127
                add(text(tag.copyOfRange(97, end), Charsets.ISO_8859_1))
            }
            // An appended v2.4 tag has a footer, optionally before the v1 tag.
            val footerEnd = if (hasTag) size - 128 else size
            if (footerEnd >= 20) {
                val footer = read(footerEnd - 10, 10)
                if (kind(footer, 0, 3) == "3DI") {
                    val start = footerEnd - 20 - sync(footer, 6)
                    require(start >= 0)
                    if (start != 0L) {
                        require(kind(read(start, 3), 0, 3) == "ID3")
                        id3(start)
                    }
                }
            }
        }
        private fun flac() {
            var position = 4L
            while (true) {
                val h = read(position, 4)
                val end = position + 4 + number(h, 1, 3)
                require(end <= size && h[0].toInt() and 127 != 127)
                if (h[0].toInt() and 127 == 4) {
                    var cursor = position + 4
                    val vendor = number(read(cursor, 4, end), little = true)
                    cursor += 4
                    require(vendor <= end - cursor)
                    cursor += vendor
                    val count = number(read(cursor, 4, end), little = true)
                    cursor += 4
                    require(count <= 4096)
                    repeat(count.toInt()) {
                        val length = number(read(cursor, 4, end), little = true)
                        cursor += 4
                        require(length <= end - cursor)
                        val prefix = kind(read(cursor, minOf(length, 12).toInt(), end), 0, minOf(length, 12).toInt())
                        val key = prefix.substringBefore('=', "").uppercase(Locale.ROOT)
                        if (key == "COMMENT" || key == "DESCRIPTION") {
                            require(length <= 16384)
                            add(text(read(cursor + key.length + 1, length.toInt() - key.length - 1, end), Charsets.UTF_8))
                        }
                        cursor += length
                    }
                    require(cursor == end)
                }
                position = end
                if (h[0].toInt() and 128 != 0) break
            }
        }
        private fun boxes(start: Long, end: Long, parent: String) {
            var position = start
            while (position < end) {
                val h = read(position, 8, end)
                val key = kind(h, 4)
                var header = 8
                var length = number(h)
                if (length == 1L) { length = number(read(position + 8, 8, end), count = 8); header = 16 }
                if (length == 0L) length = end - position
                require(length >= header && length <= end - position)
                val body = position + header
                val limit = position + length
                when {
                    parent == "root" && key == "moov" || parent == "moov" && key == "udta" ||
                        parent == "meta" && key == "ilst" || parent == "ilst" && key == "\u00a9cmt" -> boxes(body, limit, key)
                    (parent == "moov" || parent == "udta") && key == "meta" -> {
                        require(number(read(body, 4, limit)) == 0L)
                        boxes(body + 4, limit, key)
                    }
                    parent == "\u00a9cmt" && key == "data" -> {
                        val data = read(body, 8, limit)
                        val type = number(data)
                        require(type == 1L || type == 2L)
                        val length = limit - body - 8
                        require(length in 0..16384)
                        add(text(read(body + 8, length.toInt(), limit),
                            if (type == 1L) Charsets.UTF_8 else Charsets.UTF_16BE).removePrefix("\uFEFF"))
                    }
                }
                position = limit
            }
        }
    }
}
