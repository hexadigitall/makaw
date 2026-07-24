package com.hexadigitall.makaw

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MediaSessionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.getStringExtra("mediaAction") ?: return
        MediaSessionService.flutterCallback?.invoke(action, intent.getLongExtra("position", 0))
    }
}
