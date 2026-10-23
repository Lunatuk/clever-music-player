package dev.lunatuk.clever_music_player

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class AndroidMediaPrivateFilesTest {
    private fun fixture(action: (File,File,File,File) -> Unit) {
        val base = Files.createTempDirectory("cmp_private_media_").toFile().canonicalFile
        val root = File(base,"private").also { check(it.mkdir()) }
        val stage = File(root,"staging").also { check(it.mkdir()) }
        val input = File(stage,"исходник-😀.part").also { it.writeBytes(byteArrayOf(1,2,3)) }
        val output = File(stage,"output.part").also { check(it.createNewFile()) }
        val outside = File(base,"outside.part").also { it.writeBytes(byteArrayOf(9)) }
        try { action(root,input,output,outside) }
        finally {
            // Known flat fixture only; no recursive traversal or linked cleanup.
            for (file in listOf(input,output,outside,stage,root,base)) check(file.delete())
        }
    }
    private fun rejected(action: () -> Unit) {
        try { action(); fail("request must be rejected") } catch (_: IllegalArgumentException) {}
    }
    @Test fun unicodeAndAliasedParentProduceTheCanonicalUtf8File() = fixture { root,input,_,_ ->
        val alias = File(input.parentFile,"../staging/${input.name}")
        val bytes = privateMediaPath(root,alias.path,false)
        assertEquals(input.canonicalPath,String(bytes,Charsets.UTF_8))
        assertArrayEquals(input.canonicalPath.toByteArray(Charsets.UTF_8),bytes)
    }
    @Test fun sourceMustExistAndOutputMustBeEmpty() = fixture { root,input,output,_ ->
        assertNotNull(privateMediaPath(root,input.path,false))
        assertNotNull(privateMediaPath(root,output.path,true))
        rejected { privateMediaPath(root,input.path,true) }
        rejected { privateMediaPath(root,output.path,false) }
        rejected { privateMediaPath(root,File(root,"missing.part").path,false) }
        assertArrayEquals(byteArrayOf(1,2,3),input.readBytes())
    }
    @Test fun outsideRootsDirectoriesAndRelativeInputsAreRejected() = fixture { root,_,_,outside ->
        rejected { privateMediaPath(root,outside.path,false) }
        rejected { privateMediaPath(root,root.path,false) }
        rejected { privateMediaPath(root,"staging/input.part",false) }
        rejected { privateMediaPath(root,File(root,"../outside.part").path,false) }
    }
    @Test fun requestIsBoundedAndCannotContainNul() = fixture { root,input,_,_ ->
        rejected { privateMediaPath(root,null,false) }
        rejected { privateMediaPath(root,input.path + "\u0000",false) }
        rejected { privateMediaPath(root,"x".repeat(8193),false) }
    }
}
