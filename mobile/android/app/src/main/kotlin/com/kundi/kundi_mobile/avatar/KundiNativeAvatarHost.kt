package com.kundi.kundi_mobile.avatar

import android.app.Activity
import com.kundi.kundi_mobile.BuildConfig
import io.flutter.embedding.engine.FlutterEngine

object KundiNativeAvatarHost {
    private const val pluginClassName =
        "com.kundi.kundi_mobile.avatar.KundiNativeAvatarPlugin"

    fun register(activity: Activity, flutterEngine: FlutterEngine) {
        if (!BuildConfig.KUNDI_HOME_REALTIME_AVATAR_ENABLED) return
        invoke(
            methodName = "registerWith",
            parameterTypes = arrayOf(Activity::class.java, FlutterEngine::class.java),
            arguments = arrayOf(activity, flutterEngine),
        )
    }

    fun onResume() {
        if (BuildConfig.KUNDI_HOME_REALTIME_AVATAR_ENABLED) {
            invoke("onHostResume")
        }
    }

    fun onPause() {
        if (BuildConfig.KUNDI_HOME_REALTIME_AVATAR_ENABLED) {
            invoke("onHostPause")
        }
    }

    fun onAppUiHidden() {
        if (BuildConfig.KUNDI_HOME_REALTIME_AVATAR_ENABLED) {
            invoke("onAppUiHidden")
        }
    }

    fun onTrimMemory(level: Int) {
        if (!BuildConfig.KUNDI_HOME_REALTIME_AVATAR_ENABLED) return
        invoke(
            methodName = "onTrimMemory",
            parameterTypes = arrayOf(Int::class.javaPrimitiveType!!),
            arguments = arrayOf(level),
        )
    }

    fun onLowMemory() {
        if (BuildConfig.KUNDI_HOME_REALTIME_AVATAR_ENABLED) {
            invoke("onLowMemory")
        }
    }

    fun onActivityDestroy(activity: Activity) {
        if (!BuildConfig.KUNDI_HOME_REALTIME_AVATAR_ENABLED) return
        invoke(
            methodName = "onHostDestroy",
            parameterTypes = arrayOf(Activity::class.java),
            arguments = arrayOf(activity),
        )
    }

    private fun invoke(
        methodName: String,
        parameterTypes: Array<Class<*>> = emptyArray(),
        arguments: Array<Any> = emptyArray(),
    ) {
        runCatching {
            Class.forName(pluginClassName)
                .getMethod(methodName, *parameterTypes)
                .invoke(null, *arguments)
        }.onFailure { error ->
            throw IllegalStateException(
                "Native avatar integration is enabled but unavailable: $methodName",
                error,
            )
        }
    }
}
