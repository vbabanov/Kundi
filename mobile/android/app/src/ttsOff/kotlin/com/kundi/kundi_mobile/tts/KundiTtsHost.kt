package com.kundi.kundi_mobile.tts

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine

/** No registration, channels, SDK classes or native libraries in TTS-off builds. */
object KundiTtsHost {
    fun register(activity: Activity, engine: FlutterEngine) {}

    fun onPause() {}

    fun onDestroy() {}
}
