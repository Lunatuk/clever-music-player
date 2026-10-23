package dev.lunatuk.clever_music_player

import java.io.File

/** Normalize parent aliases such as /data/user/0, but reject a link in the
 * final component. Native open repeats O_NOFOLLOW/fstat/size/identity checks. */
internal fun privateMediaPath(root: File, raw: String?, output: Boolean): ByteArray {
    require(root.canonicalFile == root.absoluteFile && root.isDirectory)
    require(raw != null && raw.length <= 8192 && !raw.contains('\u0000'))
    val requested = File(raw)
    require(requested.isAbsolute)
    val file = File(requested.parentFile!!.canonicalFile, requested.name)
    require(file.canonicalFile == file.absoluteFile && file.canonicalPath.startsWith(root.path + File.separator))
    require(file.isFile && (if (output) file.length() == 0L else file.length() in 1..(8L*1024*1024*1024)))
    return file.path.toByteArray(Charsets.UTF_8).also { require(it.size <= 16384) }
}
