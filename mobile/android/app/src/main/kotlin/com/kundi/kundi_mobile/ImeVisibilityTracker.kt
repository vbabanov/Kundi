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
