package com.kundi.kundi_mobile.avatar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KundiPresentationPrimingTest {
    private val config =
        KundiPresentationPrimingConfig(
            minimumSubmittedFrames = 18,
            minimumDurationMillis = 700L,
            timeoutMillis = 1_500L,
        )

    @Test
    fun `fewer than 18 successful submissions cannot complete priming`() {
        val tracker = tracker()

        repeat(17) { index ->
            assertNull(tracker.onFrameSubmitted(100L + index * 50L))
        }

        assertTrue(tracker.isActive)
    }

    @Test
    fun `18 submissions before 700 ms cannot complete priming`() {
        val tracker = tracker()

        repeat(18) { index ->
            assertNull(tracker.onFrameSubmitted(100L + index * 30L))
        }

        assertTrue(tracker.isActive)
    }

    @Test
    fun `frame count and duration together emit one primed result`() {
        val tracker = tracker()

        repeat(17) { index ->
            assertNull(tracker.onFrameSubmitted(100L + index * 40L))
        }
        val result = tracker.onFrameSubmitted(800L)

        assertNotNull(result)
        assertEquals(18, result!!.submittedFrameCount)
        assertEquals(700L, result.elapsedMillis)
        assertFalse(tracker.isActive)
        assertNull(tracker.onFrameSubmitted(900L))
    }

    @Test
    fun `skipped renderer callbacks do not increment submitted frames`() {
        val tracker = tracker()

        repeat(17) { index -> tracker.onFrameSubmitted(100L + index * 40L) }
        assertTrue(tracker.isActive)
        assertEquals(18, tracker.onFrameSubmitted(800L)?.submittedFrameCount)
    }

    @Test
    fun `surface reset cancels priming and a new generation can begin`() {
        val tracker = tracker()
        repeat(5) { index -> tracker.onFrameSubmitted(100L + index * 40L) }

        assertTrue(tracker.reset())
        assertFalse(tracker.isActive)
        assertTrue(
            tracker.begin(
                request(rendererGeneration = 2, surfaceGeneration = 2),
            ),
        )
    }

    @Test
    fun `timeout preserves fallback and reports successful frame count`() {
        val tracker = tracker()
        repeat(4) { index -> tracker.onFrameSubmitted(100L + index * 40L) }

        assertNull(tracker.onTimeout(1_499L))
        val result = tracker.onTimeout(1_500L)

        assertNotNull(result)
        assertEquals(4, result!!.submittedFrameCount)
        assertFalse(tracker.isActive)
    }

    @Test
    fun `completed event is emitted once for a renderer and surface generation`() {
        val tracker = tracker()
        repeat(17) { index -> tracker.onFrameSubmitted(100L + index * 40L) }
        assertNotNull(tracker.onFrameSubmitted(800L))

        assertFalse(tracker.begin(request()))
        assertTrue(tracker.begin(request(rendererGeneration = 2)))
    }

    @Test
    fun `fatal renderer reset cancels priming and suppresses late completion`() {
        val tracker = tracker()
        repeat(17) { index -> tracker.onFrameSubmitted(100L + index * 40L) }

        assertTrue(tracker.reset())
        assertFalse(tracker.isActive)
        assertNull(tracker.onFrameSubmitted(800L))
        assertNull(tracker.onTimeout(1_500L))
    }

    private fun tracker(): KundiPresentationPrimingTracker =
        KundiPresentationPrimingTracker(config).also { tracker ->
            assertTrue(tracker.begin(request()))
        }

    private fun request(
        rendererGeneration: Int = 1,
        surfaceGeneration: Int = 1,
    ) = KundiPresentationPrimingRequest(
        rendererGeneration = rendererGeneration,
        textureId = 42L,
        surfaceGeneration = surfaceGeneration,
        requestedAtMillis = 0L,
    )
}
