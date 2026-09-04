package com.kundi.kundi_mobile

import com.kundi.kundi_mobile.avatar.KundiNativeAvatarHost
import com.kundi.kundi_mobile.speech.KundiSystemSpeechHost
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        KundiNativeAvatarHost.register(this, flutterEngine)
        if (BuildConfig.KUNDI_VOICE_INPUT_ENABLED) {
            KundiSystemSpeechHost.register(this, flutterEngine)
        }
    }

    override fun onResume() {
        super.onResume()
        KundiNativeAvatarHost.onResume()
    }

    override fun onPause() {
        if (BuildConfig.KUNDI_VOICE_INPUT_ENABLED) {
            KundiSystemSpeechHost.onPause()
        }
        KundiNativeAvatarHost.onPause()
        super.onPause()
    }

    override fun onStop() {
        KundiNativeAvatarHost.onAppUiHidden()
        super.onStop()
    }

    override fun onTrimMemory(level: Int) {
        KundiNativeAvatarHost.onTrimMemory(level)
        super.onTrimMemory(level)
    }

    override fun onLowMemory() {
        KundiNativeAvatarHost.onLowMemory()
        super.onLowMemory()
    }

    override fun onDestroy() {
        if (BuildConfig.KUNDI_VOICE_INPUT_ENABLED) {
            KundiSystemSpeechHost.onActivityDestroy(this)
        }
        KundiNativeAvatarHost.onActivityDestroy(this)
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (!BuildConfig.KUNDI_VOICE_INPUT_ENABLED ||
            !KundiSystemSpeechHost.onRequestPermissionsResult(requestCode, permissions, grantResults)
        ) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
