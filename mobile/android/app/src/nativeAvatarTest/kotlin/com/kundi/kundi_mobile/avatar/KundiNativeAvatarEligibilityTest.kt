package com.kundi.kundi_mobile.avatar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KundiNativeAvatarEligibilityTest {
    @Test
    fun `Redmi class arm64 Android 10 profile is eligible`() {
        val decision =
            KundiNativeAvatarEligibility.evaluate(
                profile(apiLevel = 29, memoryClassMb = 256),
            )

        assertTrue(decision.eligible)
        assertTrue(decision.reasons.isEmpty())
        assertNull(
            decision.payload(
                status = "cached",
                filamentInitialized = true,
            )["minimumMemoryClassMb"],
        )
    }

    @Test
    fun `Android 14 arm64 profile is eligible without a guessed memory threshold`() {
        val decision =
            KundiNativeAvatarEligibility.evaluate(
                profile(apiLevel = 34, memoryClassMb = 192),
            )

        assertTrue(decision.eligible)
        assertEquals(192, decision.profile.memoryClassMb)
    }

    @Test
    fun `unsupported API ABI low RAM and graphics are named`() {
        val decision =
            KundiNativeAvatarEligibility.evaluate(
                profile(
                    apiLevel = 28,
                    supportedAbis = listOf("armeabi-v7a"),
                    isLowRamDevice = true,
                    requiredGlEsVersion = 0x00020000,
                ),
            )

        assertFalse(decision.eligible)
        assertEquals(
            listOf(
                "api_too_old",
                "arm64_unavailable",
                "low_ram_device",
                "gles_3_unavailable",
            ),
            decision.reasons,
        )
    }

    private fun profile(
        apiLevel: Int,
        supportedAbis: List<String> = listOf("arm64-v8a", "armeabi-v7a"),
        isLowRamDevice: Boolean = false,
        memoryClassMb: Int = 256,
        requiredGlEsVersion: Int = 0x00030002,
    ) =
        KundiNativeAvatarDeviceProfile(
            apiLevel = apiLevel,
            supportedAbis = supportedAbis,
            isLowRamDevice = isLowRamDevice,
            memoryClassMb = memoryClassMb,
            requiredGlEsVersion = requiredGlEsVersion,
        )
}
