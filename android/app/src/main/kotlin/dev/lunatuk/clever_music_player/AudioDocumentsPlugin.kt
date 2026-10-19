package dev.lunatuk.clever_music_player

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.CancellationSignal
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap

/** SAF boundary. Library imports stay read-only; download grants are explicit. */
class AudioDocumentsPlugin : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var appContext: Context
    private val contentResolver get() = appContext.contentResolver
    private var activityBinding: ActivityPluginBinding? = null
    private var pickerResult: MethodChannel.Result? = null
    private var documentsChannel: MethodChannel? = null
    private data class FolderSession(val uri: Uri, val cancel: CancellationSignal, val walker: DocumentTreeWalker)
    private val folders = ConcurrentHashMap<Int, FolderSession>()
    private var nextFolderId = 1
    @Volatile private var destroyed = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        documentsChannel = MethodChannel(binding.binaryMessenger,
            "dev.lunatuk.clever_music_player/audio_documents").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAudio" -> pickAudio(result)
                    "pickAudioFolder" -> pickAudioFolder(result)
                    "pickDownloadFolder" -> pickAudioFolder(result, forDownload = true)
                    "inspectDownloadFolder" -> onWorker(result) {
                        val uri = call.argument<String>("uri")?.let(Uri::parse) ?: error("invalid_tree")
                        check(uri.scheme == "content" && DocumentsContract.isTreeUri(uri) && uri.pathSegments.size == 2)
                        val grant = contentResolver.persistedUriPermissions.firstOrNull { it.uri == uri }
                        val readable = grant?.isReadPermission == true
                        val writable = grant?.isWritePermission == true
                        if (!readable) {
                            mapOf("readable" to false, "writable" to writable, "canCreate" to false)
                        } else {
                            val root = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
                            contentResolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                                DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_FLAGS),
                                null, null, null).use { cursor ->
                                check(cursor != null && cursor.moveToFirst())
                                val directory = cursor.getString(1) == DocumentsContract.Document.MIME_TYPE_DIR
                                val canCreate = directory && !cursor.isNull(2) &&
                                    (cursor.getLong(2) and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE.toLong()) != 0L
                                mapOf("readable" to directory, "writable" to writable,
                                    "canCreate" to canCreate, "name" to cursor.getString(0)?.take(256))
                            }
                        }
                    }
                    "listAudioFolderGrants" -> onWorker(result) {
                        contentResolver.persistedUriPermissions.filter {
                            it.isReadPermission && DocumentsContract.isTreeUri(it.uri) && it.uri.pathSegments.size == 2
                        }.map { it.uri.toString() }
                    }
                    "inspectAudioFolder" -> onWorker(result) {
                        val uri = call.argument<String>("uri")?.let(Uri::parse) ?: error("invalid_tree")
                        check(uri.scheme == "content" && DocumentsContract.isTreeUri(uri) && uri.pathSegments.size == 2)
                        if (!hasPersistentRead(uri)) {
                            mapOf("readable" to false)
                        } else {
                            val root = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
                            contentResolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                                DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null).use { cursor ->
                                check(cursor != null && cursor.moveToFirst())
                                check(cursor.getString(1) == DocumentsContract.Document.MIME_TYPE_DIR)
                                mapOf("readable" to true, "name" to cursor.getString(0))
                            }
                        }
                    }
                    "openAudioFolder" -> onWorker(result) {
                        check(folders.isEmpty())
                        val uri = Uri.parse(call.argument<String>("uri") ?: error("invalid_tree"))
                        check(uri.scheme == "content" && DocumentsContract.isTreeUri(uri) && hasPersistentRead(uri))
                        val cancel = CancellationSignal()
                        val walker = DocumentTreeWalker(DocumentsContract.getTreeDocumentId(uri), { id ->
                            val children = DocumentsContract.buildChildDocumentsUriUsingTree(uri, id)
                            val cursor = contentResolver.query(children, arrayOf(
                                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                                DocumentsContract.Document.COLUMN_MIME_TYPE,
                                DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null, cancel)
                                ?: error("unreadable_directory")
                            object : TreeDirectoryCursor {
                                override fun next(): TreeDocument? = if (!cursor.moveToNext()) null else
                                    TreeDocument(cursor.getString(0), cursor.getString(1), cursor.getString(2))
                                override fun close() = cursor.close()
                            }
                        }, cancelled = { cancel.isCanceled })
                        val id = nextFolderId++
                        folders[id] = FolderSession(uri, cancel, walker)
                        id
                    }
                    "readAudioFolderPage" -> onWorker(result) {
                        val folder = folders[call.argument<Int>("session")] ?: error("closed_folder")
                        val page = folder.walker.nextPage()
                        mapOf("uris" to page.ids.map {
                            DocumentsContract.buildDocumentUriUsingTree(folder.uri, it).toString()
                        }, "visited" to page.visited, "done" to page.done)
                    }
                    "closeAudioFolder" -> {
                        val id = call.argument<Int>("session")
                        if (id == null) {
                            result.error("invalid_session", "Некорректный обход папки.", null)
                        } else {
                            folders[id]?.cancel?.cancel()
                            onWorker(result) {
                                folders.remove(id)?.walker?.close()
                                null
                            }
                        }
                    }
                    "readAudio" -> {
                        val address = call.argument<String>("uri")
                        val uri = address?.let(Uri::parse)
                        if (uri == null || uri.scheme != "content" || uri.authority.isNullOrEmpty()) {
                            result.error("invalid_source", "Некорректный источник музыки.", null)
                        } else {
                            worker.execute {
                                try {
                                    val metadata = readAudio(uri)
                                    mainHandler.post { if (!destroyed) result.success(metadata) }
                                } catch (_: Exception) {
                                    mainHandler.post { if (!destroyed) result.error("access_lost",
                                        "Не удалось открыть файл. Выберите его заново.", null) }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun onWorker(result: MethodChannel.Result, action: () -> Any?) {
        worker.execute {
            try {
                val value = action()
                mainHandler.post { if (!destroyed) result.success(value) }
            } catch (_: Exception) {
                mainHandler.post { if (!destroyed) result.error("folder_unavailable",
                    "Не удалось прочитать папку. Проверьте доступ и выберите её заново.", null) }
            }
        }
    }

    private fun pickAudioFolder(result: MethodChannel.Result, forDownload: Boolean = false) {
        if (pickerResult != null) {
            result.error("busy", "Выбор музыки уже открыт.", null)
            return
        }
        pickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            if (forDownload) addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        try {
            val activity = activityBinding?.activity ?: throw IllegalStateException()
            activity.startActivityForResult(intent, if (forDownload) PICK_DOWNLOAD_FOLDER else PICK_FOLDER)
        } catch (_: Exception) {
            pickerResult = null
            result.error("picker_unavailable", "Системный выбор папок недоступен.", null)
        }
    }

    private fun pickAudio(result: MethodChannel.Result) {
        if (pickerResult != null) {
            result.error("busy", "Выбор музыки уже открыт.", null)
            return
        }
        pickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            val activity = activityBinding?.activity ?: throw IllegalStateException()
            activity.startActivityForResult(intent, PICK_AUDIO)
        } catch (_: Exception) {
            pickerResult = null
            result.error("picker_unavailable", "Системный выбор файлов недоступен.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_AUDIO && requestCode != PICK_FOLDER && requestCode != PICK_DOWNLOAD_FOLDER) return false
        val result = pickerResult ?: return true
        pickerResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return true
        }
        if (requestCode == PICK_FOLDER || requestCode == PICK_DOWNLOAD_FOLDER) {
            try {
                val uri = data.data ?: error("no_tree")
                check(uri.scheme == "content" && DocumentsContract.isTreeUri(uri) && uri.pathSegments.size == 2)
                val requested = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    (if (requestCode == PICK_DOWNLOAD_FOLDER) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
                // Require every requested flag to have been returned. Persist
                // these explicit allowed constants, never arbitrary Intent flags.
                check((data.flags and requested) == requested)
                if (requestCode == PICK_DOWNLOAD_FOLDER) {
                    contentResolver.takePersistableUriPermission(uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                } else {
                    contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                result.success(mapOf("uri" to uri.toString()))
            } catch (_: Exception) {
                result.error("folder_unavailable", "Не удалось сохранить доступ к папке.", null)
            }
            return true
        }
        val selected = linkedSetOf<Uri>()
        data.data?.let { selected.add(it) }
        data.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) clip.getItemAt(index).uri?.let { selected.add(it) }
        }
        val accepted = mutableListOf<String>()
        var skipped = 0
        for (uri in selected) {
            if (uri.scheme != "content" || uri.authority.isNullOrEmpty() || accepted.size >= MAX_SELECTION) {
                skipped++
                continue
            }
            try {
                // Request only read access, even if a provider offers write access.
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                accepted.add(uri.toString())
            } catch (_: Exception) {
                // A transient grant must not create an entry that breaks next launch.
                skipped++
            }
        }
        result.success(mapOf("uris" to accepted, "skipped" to skipped))
        return true
    }

    private fun hasPersistentRead(uri: Uri): Boolean = contentResolver.persistedUriPermissions.any {
        it.isReadPermission && (it.uri == uri ||
            (it.uri.authority == uri.authority && DocumentsContract.isTreeUri(it.uri) &&
                DocumentsContract.isTreeUri(uri) &&
                DocumentsContract.getTreeDocumentId(it.uri) == DocumentsContract.getTreeDocumentId(uri)))
    }

    private fun readAudio(uri: Uri): Map<String, Any?> {
        check(hasPersistentRead(uri))
        contentResolver.openAssetFileDescriptor(uri, "r").use { check(it != null) }
        var name: String? = null
        var size: Long? = null
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
            }
        }
        val metadata = mutableMapOf<String, Any?>("name" to name, "size" to size)
        val reader = MediaMetadataRetriever()
        try {
            reader.setDataSource(appContext, uri)
            for ((key, code) in mapOf(
                "title" to MediaMetadataRetriever.METADATA_KEY_TITLE,
                "artist" to MediaMetadataRetriever.METADATA_KEY_ARTIST,
                "album" to MediaMetadataRetriever.METADATA_KEY_ALBUM,
                "albumArtist" to MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST,
                "genre" to MediaMetadataRetriever.METADATA_KEY_GENRE,
                "durationMs" to MediaMetadataRetriever.METADATA_KEY_DURATION
            )) metadata[key] = reader.extractMetadata(code)
            reader.embeddedPicture?.let { picture -> metadata["artwork"] = thumbnail(picture) }
        } catch (_: Exception) {
            // Missing/broken tags do not make readable audio unavailable.
        } finally {
            reader.release()
        }
        return metadata
    }

    private fun thumbnail(picture: ByteArray): ByteArray? {
        if (picture.size > 8 * 1024 * 1024) return null
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(picture, 0, picture.size, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) return null
        options.inSampleSize = 1
        while (maxOf(options.outWidth, options.outHeight) / options.inSampleSize > 384) {
            options.inSampleSize *= 2
        }
        options.inJustDecodeBounds = false
        val bitmap = BitmapFactory.decodeByteArray(picture, 0, picture.size, options) ?: return null
        return try {
            val output = ByteArrayOutputStream()
            @Suppress("DEPRECATION")
            val format = if (Build.VERSION.SDK_INT >= 30) Bitmap.CompressFormat.WEBP_LOSSY
                else Bitmap.CompressFormat.WEBP
            bitmap.compress(format, 85, output)
            output.toByteArray().takeIf { it.size <= 256 * 1024 }
        } finally {
            bitmap.recycle()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    private fun detachActivity(cancelPicker: Boolean) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        if (cancelPicker) {
            pickerResult?.error("picker_closed", "Выбор музыки прерван.", null)
            pickerResult = null
        }
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity(false)
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity(true)

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        destroyed = true
        documentsChannel?.setMethodCallHandler(null)
        detachActivity(true)
        folders.values.forEach { it.cancel.cancel() }
        worker.execute {
            folders.values.forEach { try { it.walker.close() } catch (_: Exception) {} }
            folders.clear()
        }
        worker.shutdown()
    }

    private companion object {
        const val PICK_AUDIO = 417
        const val PICK_FOLDER = 418
        const val PICK_DOWNLOAD_FOLDER = 419
        const val MAX_SELECTION = 64
    }
}
