package com.kundi.kundi_mobile

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeVisibilityTrackerTest {
    @Test
    fun initialHiddenInsetsDoNotRequestRestore() {
        val tracker = ImeVisibilityTracker()

        assertFalse(tracker.onVisibilityChanged(false))
        assertFalse(tracker.isVisible)
    }

    @Test
    fun visibleToHiddenTransitionRequestsOneRestore() {
        val tracker = ImeVisibilityTracker()

        assertFalse(tracker.onVisibilityChanged(true))
        assertTrue(tracker.isVisible)
        assertTrue(tracker.onVisibilityChanged(false))
        assertFalse(tracker.onVisibilityChanged(false))
    }

    @Test
    fun eachKeyboardSessionCanRequestRestore() {
        val tracker = ImeVisibilityTracker()

        tracker.onVisibilityChanged(true)
        assertTrue(tracker.onVisibilityChanged(false))
        tracker.onVisibilityChanged(true)
        assertTrue(tracker.onVisibilityChanged(false))
    }

    @Test
    fun legacyImeOpenRequestsOneDecorFitTransition() {
        assertTrue(
            shouldEnableLegacyImeResize(
                sdkInt = 29,
                wasVisible = false,
                isVisible = true,
            ),
        )
        assertFalse(
            shouldEnableLegacyImeResize(
                sdkInt = 29,
                wasVisible = true,
                isVisible = true,
            ),
        )
    }

    @Test
    fun modernAndroidKeepsEdgeToEdgeInsetHandling() {
        assertFalse(
            shouldEnableLegacyImeResize(
                sdkInt = 30,
                wasVisible = false,
                isVisible = true,
            ),
        )
    }

    @Test
    fun legacyVisibleFrameDetectsKeyboardOcclusion() {
        assertTrue(
            isLegacyImeLikelyVisible(
                screenHeight = 2340,
                visibleBottom = 1320,
            ),
        )
    }

    @Test
    fun legacyVisibleFrameIgnoresSystemBarInsets() {
        assertFalse(
            isLegacyImeLikelyVisible(
                screenHeight = 2340,
                visibleBottom = 2208,
            ),
        )
    }

    @Test
    fun legacyVisibleFrameRejectsInvalidMeasurements() {
        assertFalse(isLegacyImeLikelyVisible(screenHeight = 0, visibleBottom = 0))
        assertFalse(
            isLegacyImeLikelyVisible(
                screenHeight = 2208,
                visibleBottom = 2340,
            ),
        )
    }
}
