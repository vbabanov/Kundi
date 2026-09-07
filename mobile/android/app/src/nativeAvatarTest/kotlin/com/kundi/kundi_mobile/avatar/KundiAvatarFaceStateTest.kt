package com.kundi.kundi_mobile.avatar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class KundiAvatarFaceStateTest {
    @Test
    fun `emotion and viseme coexist and clearing mouth preserves emotion`() {
        val face = faceState()

        face.setEmotion("Joy", 0.4f, nowNanos = 0L)
        val settledAt = 240_000_000L
        face.setViseme("A", 0.75f)
        val speaking = face.snapshot(settledAt)

        assertEquals(0.4f, speaking["Joy"]!!, 0.0001f)
        assertEquals(0.75f, speaking["A"]!!, 0.0001f)
        face.clearViseme()
        val mouthCleared = face.snapshot(settledAt)
        assertEquals(0.4f, mouthCleared["Joy"]!!, 0.0001f)
        assertFalse(mouthCleared.containsKey("A"))
    }

    @Test
    fun `emotion returns smoothly to Neutral`() {
        val face = faceState()
        face.setEmotion("Sorrow", 0.3f, nowNanos = 0L)
        face.snapshot(240_000_000L)

        face.setEmotion("Neutral", 1f, nowNanos = 240_000_000L)
        val halfway = face.snapshot(360_000_000L)
        assertTrue(face.transitionPending)
        assertTrue(halfway.getValue("Sorrow") > 0f)
        assertTrue(halfway.getValue("Neutral") > 0f)

        val settled = face.snapshot(480_000_000L)
        assertFalse(face.transitionPending)
        assertEquals(1f, settled["Neutral"]!!, 0.0001f)
        assertFalse(settled.containsKey("Sorrow"))
    }

    @Test
    fun `all facial channel weights are bounded`() {
        val face = faceState()
        assertThrows(IllegalArgumentException::class.java) {
            face.setEmotion("Joy", 1.01f, 0L)
        }
        assertThrows(IllegalArgumentException::class.java) {
            face.setViseme("A", -0.01f)
        }
        assertThrows(IllegalArgumentException::class.java) {
            face.setBlink(Float.NaN)
        }
    }

    private fun faceState() =
        KundiAvatarFaceState(
            neutralBlendShape = "Neutral",
            blinkBlendShape = "Blink",
            transitionDurationNanos = 240_000_000L,
        )
}
