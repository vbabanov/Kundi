package com.kundi.kundi_mobile

import com.kundi.kundi_mobile.avatar.KundiNativeAvatarHost
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        KundiNativeAvatarHost.register(this, flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        KundiNativeAvatarHost.onResume()
    }

    override fun onPause() {
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
        KundiNativeAvatarHost.onActivityDestroy(this)
        super.onDestroy()
    }
}
