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
}
