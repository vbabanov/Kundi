package com.kundi.kundi_mobile.avatar

import android.app.Activity
import android.content.ComponentCallbacks2
import android.os.Build
import android.util.Log
import androidx.annotation.Keep
import com.google.android.filament.gltfio.Gltfio
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

internal fun shouldReleaseAvatarForMemoryLevel(
    level: Int,
    apiLevel: Int = Build.VERSION.SDK_INT,
): Boolean =
    level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN ||
        (apiLevel < 34 && level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE)

@Keep
object KundiNativeAvatarPlugin {
    private var registeredEngine = WeakReference<FlutterEngine>(null)
    private var initialized = false
    private var initializationFailure: String? = null
    private var prewarmChannel: MethodChannel? = null
    private var textureManager: KundiNativeAvatarTextureManager? = null

    @JvmStatic
    @Keep
    fun registerWith(activity: Activity, flutterEngine: FlutterEngine) {
        if (registeredEngine.get() === flutterEngine) return

        val applicationContext = activity.applicationContext
        val eligibility = KundiNativeAvatarEligibility.inspect(applicationContext)
        if (eligibility.eligible && !initialized && initializationFailure == null) {
            runCatching(Gltfio::init)
                .onSuccess { initialized = true }
                .onFailure {
                    initializationFailure =
                        it.message?.takeIf(String::isNotBlank)
                            ?: it.javaClass.simpleName
                }
        }
        val runtimeEligible = eligibility.eligible && initialized
        Log.i(
            logTag,
            "eligibility=${
                eligibility.payload(
                    status = if (runtimeEligible) "eligible" else "unsupported",
                    filamentInitialized = initialized,
                )
            }",
        )
        prewarmChannel?.setMethodCallHandler(null)
        prewarmChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "kundi/native_avatar/prewarm",
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    if (call.method != "prewarm") {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                    if (!runtimeEligible) {
                        result.success(
                            eligibility.payload(
                                status = "unsupported",
                                filamentInitialized = initialized,
                            ) +
                                mapOf(
                                    "reasons" to
                                        eligibility.reasons +
                                            listOfNotNull(
                                                initializationFailure?.let {
                                                    "filament_init_failed"
                                                },
                                            ),
                                ),
                        )
                        return@setMethodCallHandler
                    }
                    KundiNativeAvatarModelCache.prewarm(applicationContext) {
                        val status = it["status"] as? String ?: "failed"
                        result.success(
                            eligibility.payload(
                                status = status,
                                filamentInitialized = true,
                                modelPrewarmed = status == "cached" || status == "alreadyCached",
                            ) + it,
                        )
                    }
                }
            }

        textureManager?.dispose()
        textureManager =
            KundiNativeAvatarTextureManager(
                context = applicationContext,
                messenger = flutterEngine.dartExecutor.binaryMessenger,
                textureRegistry = flutterEngine.renderer,
                rendererEligible = runtimeEligible,
            )

        registeredEngine = WeakReference(flutterEngine)
    }

    @JvmStatic
    @Keep
    fun onHostResume() {
        textureManager?.onHostResume()
    }

    @JvmStatic
    @Keep
    fun onHostPause() {
        textureManager?.onHostPause()
    }

    @JvmStatic
    @Keep
    fun onAppUiHidden() {
        textureManager?.onAppUiHidden()
        KundiNativeAvatarModelCache.clear()
    }

    @JvmStatic
    @Keep
    fun onTrimMemory(level: Int) {
        if (!shouldReleaseAvatarForMemoryLevel(level)) return
        textureManager?.onTrimMemory(level)
        KundiNativeAvatarModelCache.clear()
    }

    @JvmStatic
    @Keep
    fun onLowMemory() {
        textureManager?.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_COMPLETE)
        KundiNativeAvatarModelCache.clear()
    }

    @JvmStatic
    @Keep
    fun onHostDestroy(@Suppress("UNUSED_PARAMETER") activity: Activity) {
        registeredEngine.clear()
        prewarmChannel?.setMethodCallHandler(null)
        prewarmChannel = null
        textureManager?.dispose()
        textureManager = null
        KundiNativeAvatarModelCache.clear()
    }

    private const val logTag = "KundiNativeAvatar"
}
