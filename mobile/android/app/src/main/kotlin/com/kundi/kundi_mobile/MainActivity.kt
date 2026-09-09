package com.kundi.kundi_mobile

import android.graphics.Color
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.ViewTreeObserver
import android.view.WindowManager
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.kundi.kundi_mobile.avatar.KundiNativeAvatarHost
import com.kundi.kundi_mobile.speech.KundiSystemSpeechHost
import com.kundi.kundi_mobile.tts.KundiTtsHost
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val imeVisibilityTracker = ImeVisibilityTracker()
    private var insetsImeVisible = false
    private var legacyFrameImeVisible = false
    private var lastLegacyImeInsetPixels = -1
    private var legacyImeLayoutListener: ViewTreeObserver.OnGlobalLayoutListener? = null
    private var legacyImeLayoutChannel: MethodChannel? = null
    private val restoreAfterIme = Runnable {
        if (window.decorView.hasWindowFocus() && !imeVisibilityTracker.isVisible) {
            applyImmersiveMode("ime-hidden")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureEdgeToEdgeWindow()
        installImeVisibilityTracking()
        applyImmersiveMode("activity-created")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        KundiNativeAvatarHost.register(this, flutterEngine)
        KundiTtsHost.register(this, flutterEngine)
        if (BuildConfig.KUNDI_VOICE_INPUT_ENABLED) {
            KundiSystemSpeechHost.register(this, flutterEngine)
        }
        legacyImeLayoutChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LEGACY_IME_LAYOUT_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != PREPARE_LEGACY_IME_LAYOUT_METHOD) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (shouldPrepareLegacyImeLayout(Build.VERSION.SDK_INT)) {
                    // This must happen before Flutter asks Android to show the
                    // keyboard. MIUI 12 does not report IME insets while the
                    // existing edge-to-edge layout is active.
                    WindowCompat.setDecorFitsSystemWindows(window, true)
                    Log.d(IMMERSIVE_LOG_TAG, "legacy IME layout prepared")
                }
                result.success(null)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        applyImmersiveMode("activity-resumed")
        KundiNativeAvatarHost.onResume()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && !imeVisibilityTracker.isVisible) {
            applyImmersiveMode("window-focus-restored")
        }
    }

    override fun onPause() {
        KundiTtsHost.onPause()
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
        val decorView = window.decorView
        decorView.removeCallbacks(restoreAfterIme)
        ViewCompat.setOnApplyWindowInsetsListener(decorView, null)
        legacyImeLayoutListener?.let { listener ->
            if (decorView.viewTreeObserver.isAlive) {
                decorView.viewTreeObserver.removeOnGlobalLayoutListener(listener)
            }
        }
        legacyImeLayoutListener = null
        legacyImeLayoutChannel?.setMethodCallHandler(null)
        legacyImeLayoutChannel = null
        KundiTtsHost.onDestroy()
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
        applyImmersiveMode("permission-result")
    }

    // Android 10 still needs the pre-API-35 color setters for a transparent
    // three-button navigation-bar surface behind transient system UI.
    @Suppress("DEPRECATION")
    private fun configureEdgeToEdgeWindow() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
    }

    private fun installImeVisibilityTracking() {
        val decorView = window.decorView
        ViewCompat.setOnApplyWindowInsetsListener(decorView) { _, insets ->
            insetsImeVisible = insets.isVisible(WindowInsetsCompat.Type.ime())
            updateImeVisibility()
            insets
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            val visibleFrame = Rect()
            val listener = ViewTreeObserver.OnGlobalLayoutListener {
                decorView.getWindowVisibleDisplayFrame(visibleFrame)
                val screenHeight = maxOf(
                    resources.displayMetrics.heightPixels,
                    decorView.rootView.height,
                )
                legacyFrameImeVisible = isLegacyImeLikelyVisible(
                    screenHeight = screenHeight,
                    visibleBottom = visibleFrame.bottom,
                )
                publishLegacyImeInset(
                    if (legacyFrameImeVisible) {
                        (screenHeight - visibleFrame.bottom).coerceAtLeast(0)
                    } else {
                        0
                    },
                )
                updateImeVisibility()
            }
            legacyImeLayoutListener = listener
            decorView.viewTreeObserver.addOnGlobalLayoutListener(listener)
        }
        ViewCompat.requestApplyInsets(decorView)
    }

    private fun publishLegacyImeInset(bottomInsetPixels: Int) {
        if (bottomInsetPixels == lastLegacyImeInsetPixels) return
        lastLegacyImeInsetPixels = bottomInsetPixels
        legacyImeLayoutChannel?.invokeMethod(
            LEGACY_IME_INSET_CHANGED_METHOD,
            bottomInsetPixels,
        )
        Log.d(IMMERSIVE_LOG_TAG, "legacy IME inset: $bottomInsetPixels")
    }

    private fun updateImeVisibility() {
        val decorView = window.decorView
        val imeVisible = insetsImeVisible || legacyFrameImeVisible
        val imeWasVisible = imeVisibilityTracker.isVisible
        val enableLegacyImeResize = shouldEnableLegacyImeResize(
            sdkInt = Build.VERSION.SDK_INT,
            wasVisible = imeWasVisible,
            isVisible = imeVisible,
        )
        val shouldRestoreAfterIme =
            imeVisibilityTracker.onVisibilityChanged(imeVisible)
        if (imeVisible) {
            decorView.removeCallbacks(restoreAfterIme)
            // On Android 8-10, edge-to-edge decor does not resize the
            // Flutter surface for adjustResize. Temporarily let the platform
            // fit the decor so the composer stays above the IME.
            if (enableLegacyImeResize) {
                WindowCompat.setDecorFitsSystemWindows(window, true)
            }
        } else if (shouldRestoreAfterIme) {
            decorView.removeCallbacks(restoreAfterIme)
            decorView.postDelayed(restoreAfterIme, IME_SYSTEM_UI_COOLDOWN_MILLIS)
        }
    }

    private fun applyImmersiveMode(reason: String) {
        configureEdgeToEdgeWindow()
        WindowInsetsControllerCompat(window, window.decorView).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
            hide(WindowInsetsCompat.Type.systemBars())
        }
        Log.d(IMMERSIVE_LOG_TAG, "system bars hidden: $reason")
    }

    private companion object {
        const val LEGACY_IME_LAYOUT_CHANNEL =
            "com.kundi.kundi_mobile/legacy_ime_layout"
        const val PREPARE_LEGACY_IME_LAYOUT_METHOD = "prepareForIme"
        const val LEGACY_IME_INSET_CHANGED_METHOD = "legacyImeInsetChanged"
        const val IME_SYSTEM_UI_COOLDOWN_MILLIS = 1_100L
        const val IMMERSIVE_LOG_TAG = "KundiImmersive"
    }
}
