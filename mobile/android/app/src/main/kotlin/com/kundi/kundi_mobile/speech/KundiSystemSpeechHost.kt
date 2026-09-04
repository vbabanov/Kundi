package com.kundi.kundi_mobile.speech

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine

object KundiSystemSpeechHost {
    private var plugin: KundiSystemSpeechPlugin? = null

    fun register(activity: Activity, flutterEngine: FlutterEngine) {
        plugin?.dispose()
        plugin = KundiSystemSpeechPlugin(activity, flutterEngine.dartExecutor.binaryMessenger)
    }

    fun onPause() {
        plugin?.cancelForLifecycle()
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean =
        plugin?.onRequestPermissionsResult(requestCode, permissions, grantResults) ?: false

    fun onActivityDestroy(activity: Activity) {
        plugin?.takeIf { it.activity === activity }?.dispose()
        plugin = null
    }
}
