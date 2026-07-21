package com.example.makaw_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder

class MediaSessionService : Service() {

    companion object {
        const val CHANNEL_ID = "com.example.makaw_mobile.music"
        const val NOTIFICATION_ID = 1001
        const val ACTION_SHOW = "SHOW_NOTIFICATION"
        const val ACTION_HIDE = "HIDE_NOTIFICATION"
        const val EXTRA_TITLE = "title"
        const val EXTRA_ARTIST = "artist"
        const val EXTRA_IS_PLAYING = "isPlaying"
        const val EXTRA_POSITION = "position"
        const val EXTRA_DURATION = "duration"
        const val CALLBACK_PLAY = "play"
        const val CALLBACK_PAUSE = "pause"
        const val CALLBACK_NEXT = "next"
        const val CALLBACK_PREV = "prev"
        const val CALLBACK_SEEK = "seek"

        var flutterCallback: ((String, Long) -> Unit)? = null
        private var currentService: MediaSessionService? = null
        private var lastTitle: String = "Unknown"
        private var lastArtist: String = ""

        fun updatePlaybackState(isPlaying: Boolean, positionMs: Long) {
            currentService?.let { service ->
                val session = service.mediaSession ?: return@let
                val state = PlaybackState.Builder()
                    .setActions(
                        PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackState.ACTION_STOP or PlaybackState.ACTION_SEEK_TO
                    )
                    .setState(
                        if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                        positionMs, 1.0f
                    )
                    .build()
                session.setPlaybackState(state)
                // Force notification update for MIUI compatibility
                service.showNotification(lastTitle, lastArtist, isPlaying)
            }
        }
    }

    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        currentService = this
        createChannel()
        setupMediaSession()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            mgr.deleteNotificationChannel(CHANNEL_ID)
            val ch = NotificationChannel(CHANNEL_ID, "Music Playback", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Shows currently playing music"
            mgr.createNotificationChannel(ch)
        }
    }

    private fun setupMediaSession() {
        mediaSession = MediaSession(this, "MakawMediaSession")
        mediaSession?.setCallback(object : MediaSession.Callback() {
            override fun onPlay() { flutterCallback?.invoke(CALLBACK_PLAY, 0) }
            override fun onPause() { flutterCallback?.invoke(CALLBACK_PAUSE, 0) }
            override fun onSkipToNext() { flutterCallback?.invoke(CALLBACK_NEXT, 0) }
            override fun onSkipToPrevious() { flutterCallback?.invoke(CALLBACK_PREV, 0) }
            override fun onSeekTo(pos: Long) { flutterCallback?.invoke(CALLBACK_SEEK, pos) }
            override fun onStop() {
                flutterCallback?.invoke(CALLBACK_PAUSE, 0)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        })
        mediaSession?.isActive = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Unknown"
                val artist = intent.getStringExtra(EXTRA_ARTIST) ?: ""
                val isPlaying = intent.getBooleanExtra(EXTRA_IS_PLAYING, false)
                val position = intent.getLongExtra(EXTRA_POSITION, 0)
                val duration = intent.getLongExtra(EXTRA_DURATION, 0)
                showNotification(title, artist, isPlaying)
                updateSession(title, artist, isPlaying, position, duration)
            }
            ACTION_HIDE -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    @Suppress("DEPRECATION")
    private fun showNotification(title: String, artist: String, isPlaying: Boolean) {
        lastTitle = title
        lastArtist = artist
        val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseAction = if (isPlaying) CALLBACK_PAUSE else CALLBACK_PLAY

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        // Tap notification to open app to now-playing page
        val openIntent = Intent(this, MainActivity::class.java).apply {
            action = "com.example.makaw_mobile.OPEN_PLAYER"
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = builder
            .setContentTitle(title)
            .setContentText(artist)
            .setSmallIcon(playPauseIcon)
            .setOngoing(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(contentPendingIntent)
            .setStyle(Notification.MediaStyle()
                .setMediaSession(mediaSession?.sessionToken)
                .setShowActionsInCompactView(0, 1, 2))
            .addAction(android.R.drawable.ic_media_previous, "Previous", mediaActionIntent(CALLBACK_PREV))
            .addAction(playPauseIcon, if (isPlaying) "Pause" else "Play", mediaActionIntent(playPauseAction))
            .addAction(android.R.drawable.ic_media_next, "Next", mediaActionIntent(CALLBACK_NEXT))
            .setPriority(Notification.PRIORITY_HIGH)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun mediaActionIntent(action: String): PendingIntent {
        val intent = Intent(this, MediaSessionReceiver::class.java).apply {
            putExtra("mediaAction", action)
        }
        return PendingIntent.getBroadcast(
            this, action.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun updateSession(title: String, artist: String, isPlaying: Boolean, position: Long, duration: Long) {
        mediaSession?.setMetadata(MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
            .putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
            .build()
        )
        val state = PlaybackState.Builder()
            .setActions(
                PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                PlaybackState.ACTION_STOP or PlaybackState.ACTION_SEEK_TO
            )
            .setState(
                if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                position, 1.0f
            )
            .build()
        mediaSession?.setPlaybackState(state)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }
}
