package com.kundi.kundi_mobile

/**
 * Reports only a real visible-to-hidden IME transition.
 *
 * Keeping this state separate prevents ordinary system-bar inset dispatches
 * from turning immersive restoration into a feedback loop.
 */
internal class ImeVisibilityTracker {
    var isVisible: Boolean = false
        private set

    fun onVisibilityChanged(visible: Boolean): Boolean {
        val keyboardWasClosed = isVisible && !visible
        isVisible = visible
        return keyboardWasClosed
    }
}

internal fun shouldEnableLegacyImeResize(
    sdkInt: Int,
    wasVisible: Boolean,
    isVisible: Boolean,
): Boolean = sdkInt < 30 && !wasVisible && isVisible

internal fun shouldPrepareLegacyImeLayout(sdkInt: Int): Boolean = sdkInt < 30

/**
 * Detects the legacy keyboard from the window's visible frame.
 *
 * Some Android 8-10 vendor builds do not expose the IME through WindowInsets
 * while edge-to-edge is active. The visible-frame bottom remains reliable on
 * those builds. A 15% threshold excludes status/navigation bars and cutouts.
 */
internal fun isLegacyImeLikelyVisible(
    screenHeight: Int,
    visibleBottom: Int,
): Boolean {
    if (screenHeight <= 0 || visibleBottom <= 0 || visibleBottom > screenHeight) {
        return false
    }
    return screenHeight - visibleBottom > screenHeight * 0.15f
}
