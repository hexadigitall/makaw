package com.example.makaw_mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.app.Activity
import android.content.Context
import android.media.AudioManager
import android.media.MediaPlayer
import android.provider.MediaStore
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.makaw_mobile/intent"
    private val SYSTEM_CHANNEL = "com.example.makaw_mobile/system"
    private val MEDIA_CHANNEL = "com.example.makaw_mobile/media"
    private var serviceStarted = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Forward media button events from the service to Flutter
        MediaSessionService.flutterCallback = { action, position ->
            val engine = flutterEngine
            if (engine != null) {
                MethodChannel(engine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
                    .invokeMethod("onMediaAction", mapOf("action" to action, "position" to position))
            }
        }

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "getInitialIntent") {
                val intent = intent
                result.success(buildIntentMap(intent))
            } else {
                result.notImplemented()
            }
        }
        val systemChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL)
        systemChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "moveTaskToBack" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                "setNavigationBarColor" -> {
                    val argb = (call.argument<Number>("color")?.toInt()) ?: 0
                    try {
                        window.navigationBarColor = argb
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            window.decorView.windowInsetsController?.apply {
                                setSystemBarsAppearance(0, android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS)
                            }
                        }
                        @Suppress("DEPRECATION")
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                            window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
                            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NAV_BAR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        val metadataChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.makaw_mobile/metadata")
        metadataChannel.setMethodCallHandler { call, result ->
            if (call.method == "extractMetadataBatch") {
                val paths = call.argument<List<String>>("paths") ?: emptyList()
                // First, build a map from MediaStore (returns metadata without file access)
                val mediaStoreMap = mutableMapOf<String, Map<String, Any?>>()
                try {
                    val cursor = contentResolver.query(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        arrayOf(
                            MediaStore.Audio.Media.DATA,
                            MediaStore.Audio.Media.TITLE,
                            MediaStore.Audio.Media.ARTIST,
                            MediaStore.Audio.Media.ALBUM,
                            MediaStore.Audio.Media.DURATION,
                        ),
                        null, null, null
                    )
                    cursor?.use {
                        while (it.moveToNext()) {
                            val filePath = it.getString(it.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)) ?: continue
                            val title = it.getString(it.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)) ?: ""
                            val artist = it.getString(it.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)) ?: ""
                            val album = it.getString(it.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)) ?: ""
                            val duration = it.getLong(it.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION))
                            mediaStoreMap[filePath] = mapOf(
                                "path" to filePath,
                                "title" to title,
                                "artist" to artist,
                                "album" to album,
                                "duration" to duration,
                            )
                        }
                    }
                    Log.d("MakawMetadata", "MediaStore returned ${mediaStoreMap.size} audio files")
                } catch (e: Exception) {
                    Log.e("MakawMetadata", "MediaStore query failed: ${e.message}")
                }

                val results = mutableListOf<Map<String, Any?>>()
                for (path in paths) {
                    // Check MediaStore first
                    val fromStore = mediaStoreMap[path]
                    if (fromStore != null) {
                        val msArtist = fromStore["artist"] as? String ?: ""
                        val msAlbum = fromStore["album"] as? String ?: ""
                        // If MediaStore has meaningful artist/album, use it
                        if (msArtist.isNotEmpty() && msArtist != "<unknown>" && msAlbum.isNotEmpty() && msAlbum != "<unknown>") {
                            results.add(fromStore)
                            continue
                        }
                        // MediaStore metadata is incomplete; try retriever as fallback
                        try {
                            val retriever = android.media.MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(path)
                                val title = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_TITLE) ?: ""
                                val artist = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_ARTIST) ?: ""
                                val album = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_ALBUM) ?: ""
                                val durationStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION) ?: "0"
                                results.add(mapOf(
                                    "path" to path,
                                    "title" to (title.ifEmpty { fromStore["title"] as? String ?: "" }),
                                    "artist" to artist,
                                    "album" to album,
                                    "duration" to (durationStr.toLongOrNull() ?: (fromStore["duration"] as? Long ?: 0L)),
                                ))
                            } finally {
                                retriever.release()
                            }
                            continue
                        } catch (_: Exception) {
                            // Retriever failed, use MediaStore result
                            results.add(fromStore)
                            continue
                        }
                    }
                    // Fallback: MediaMetadataRetriever
                    var retriever: android.media.MediaMetadataRetriever? = null
                    var success = false
                    try {
                        retriever = android.media.MediaMetadataRetriever()
                        retriever.setDataSource(path)
                        success = extractAndAdd(results, retriever, path)
                    } catch (_: Exception) {}
                    if (!success) {
                        try {
                            retriever?.release()
                            retriever = android.media.MediaMetadataRetriever()
                            val file = java.io.File(path)
                            android.os.ParcelFileDescriptor.open(file, android.os.ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                                retriever.setDataSource(pfd.fileDescriptor)
                                success = extractAndAdd(results, retriever, path)
                            }
                        } catch (_: Exception) {}
                    }
                    if (!success) {
                        Log.e("MakawMetadata", "All methods failed for $path")
                        results.add(mapOf("path" to path))
                    }
                    retriever?.release()
                }
                result.success(results)
            } else {
                result.notImplemented()
            }
        }

        // Video player control channel (volume, brightness, screenshot)
        val videoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.makaw_mobile/video_control")
        videoChannel.setMethodCallHandler { call, result ->
            val audioMgr = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (call.method) {
                "getMaxVolume" -> {
                    result.success(audioMgr.getStreamMaxVolume(AudioManager.STREAM_MUSIC))
                }
                "getVolume" -> {
                    result.success(audioMgr.getStreamVolume(AudioManager.STREAM_MUSIC))
                }
                "setVolume" -> {
                    val vol = (call.argument<Number>("volume")?.toInt()) ?: 0
                    val maxVol = audioMgr.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    audioMgr.setStreamVolume(AudioManager.STREAM_MUSIC, vol.coerceIn(0, maxVol), 0)
                    result.success(true)
                }
                "getScreenBrightness" -> {
                    val lp = window.attributes
                    val brightness = if (lp.screenBrightness < 0) 0.5f else lp.screenBrightness
                    result.success(brightness.toDouble())
                }
                "setScreenBrightness" -> {
                    val brightness = (call.argument<Number>("brightness")?.toFloat()) ?: 0.5f
                    val lp = window.attributes
                    lp.screenBrightness = brightness.coerceIn(0.01f, 1.0f)
                    window.attributes = lp
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        val mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
        mediaChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    val title = call.argument<String>("title") ?: "Unknown"
                    val artist = call.argument<String>("artist") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val position = (call.argument<Number>("position")?.toLong() ?: 0L)
                    val duration = (call.argument<Number>("duration")?.toLong() ?: 0L)
                    val intent = Intent(this, MediaSessionService::class.java).apply {
                        action = MediaSessionService.ACTION_SHOW
                        putExtra(MediaSessionService.EXTRA_TITLE, title)
                        putExtra(MediaSessionService.EXTRA_ARTIST, artist)
                        putExtra(MediaSessionService.EXTRA_IS_PLAYING, isPlaying)
                        putExtra(MediaSessionService.EXTRA_POSITION, position)
                        putExtra(MediaSessionService.EXTRA_DURATION, duration)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    serviceStarted = true
                    result.success(true)
                }
                "updateNotification" -> {
                    if (serviceStarted) {
                        val title = call.argument<String>("title") ?: "Unknown"
                        val artist = call.argument<String>("artist") ?: ""
                        val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                        val position = (call.argument<Number>("position")?.toLong() ?: 0L)
                        val duration = (call.argument<Number>("duration")?.toLong() ?: 0L)
                        val intent = Intent(this, MediaSessionService::class.java).apply {
                            action = MediaSessionService.ACTION_SHOW
                            putExtra(MediaSessionService.EXTRA_TITLE, title)
                            putExtra(MediaSessionService.EXTRA_ARTIST, artist)
                            putExtra(MediaSessionService.EXTRA_IS_PLAYING, isPlaying)
                            putExtra(MediaSessionService.EXTRA_POSITION, position)
                            putExtra(MediaSessionService.EXTRA_DURATION, duration)
                        }
                        startService(intent)
                    }
                    result.success(true)
                }
                "updatePlaybackState" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val position = (call.argument<Number>("position")?.toLong() ?: 0L)
                    MediaSessionService.updatePlaybackState(isPlaying, position)
                    result.success(true)
                }
                "stopForeground" -> {
                    if (serviceStarted) {
                        val intent = Intent(this, MediaSessionService::class.java).apply {
                            action = MediaSessionService.ACTION_HIDE
                        }
                        startService(intent)
                        serviceStarted = false
                    }
                    result.success(true)
                }
                "getNotificationChannelImportance" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val manager = getSystemService(android.app.NotificationManager::class.java)
                            val channel = manager.getNotificationChannel(MediaSessionService.CHANNEL_ID)
                            if (channel != null) {
                                result.success(channel.importance.toString())
                            } else {
                                result.success("not_found")
                            }
                        } catch (e: Exception) {
                            result.success("error:${e.message}")
                        }
                    } else {
                        result.success("pre_o")
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val engine = flutterEngine ?: return
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.invokeMethod("onNewIntent", buildIntentMap(intent))
    }

    override fun onDestroy() {
        MediaSessionService.flutterCallback = null
        super.onDestroy()
    }

    private fun buildIntentMap(intent: Intent?): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        if (intent == null) {
            result["action"] = ""
            return result
        }
        if (intent.action == "com.example.makaw_mobile.OPEN_PLAYER") {
            result["action"] = "OPEN_PLAYER"
            return result
        }
        if (intent.action != Intent.ACTION_VIEW) {
            result["action"] = ""
            return result
        }
        val uri = intent.data ?: run {
            result["action"] = intent.action ?: ""
            return result
        }
        result["action"] = intent.action ?: ""
        result["uri"] = uri.toString()
        result["mimeType"] = intent.type ?: ""
        result["scheme"] = uri.scheme ?: ""
        result["filePath"] = resolveFilePath(uri)
        return result
    }

    private fun resolveFilePath(uri: Uri): String {
        if (DocumentsContract.isDocumentUri(this, uri)) {
            val docId = DocumentsContract.getDocumentId(uri)
            if (uri.authority == "com.android.externalstorage.documents") {
                val split = docId.split(":")
                if (split.size >= 2) {
                    val type = split[0]
                    val relativePath = split[1]
                    val root = when (type) {
                        "primary" -> Environment.getExternalStorageDirectory().absolutePath
                        else -> "/storage/$type"
                    }
                    val filePath = "$root/$relativePath"
                    if (File(filePath).exists()) return filePath
                }
            }
        }
        if (uri.scheme == "content") {
            try {
                val cursor = contentResolver.query(uri, null, null, null, null)
                cursor?.use {
                    if (it.moveToFirst()) {
                        val dataIdx = it.getColumnIndex(android.provider.MediaStore.MediaColumns.DATA)
                        if (dataIdx >= 0) {
                            val data = it.getString(dataIdx)
                            if (data != null && File(data).exists()) return data
                        }
                        val nameIdx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val name = if (nameIdx >= 0) it.getString(nameIdx) else "file"
                        val cacheFile = File(cacheDir, name)
                        try {
                            applicationContext.contentResolver.openInputStream(uri)?.use { input ->
                                cacheFile.outputStream().use { output ->
                                    input.copyTo(output)
                                }
                            }
                            if (cacheFile.exists()) return cacheFile.absolutePath
                        } catch (_: Exception) {}
                    }
                }
            } catch (_: Exception) {}
        }
        return uri.toString()
    }

    private fun extractAndAdd(results: MutableList<Map<String, Any?>>, retriever: android.media.MediaMetadataRetriever, path: String): Boolean {
        val title = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_TITLE)
        val artist = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_ARTIST)
        val album = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_ALBUM)
        val duration = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
        results.add(mapOf(
            "path" to path,
            "title" to (title ?: ""),
            "artist" to (artist ?: ""),
            "album" to (album ?: ""),
            "duration" to (duration?.toLongOrNull() ?: 0L),
        ))
        return true
    }
}
