package com.kundi.kundi_mobile.avatar

import android.app.ActivityManager
import android.content.Context
import android.os.Build

internal data class KundiNativeAvatarDeviceProfile(
    val apiLevel: Int,
    val supportedAbis: List<String>,
    val isLowRamDevice: Boolean,
    val memoryClassMb: Int,
    val requiredGlEsVersion: Int,
)

internal data class KundiNativeAvatarEligibilityDecision(
    val eligible: Boolean,
    val reasons: List<String>,
    val profile: KundiNativeAvatarDeviceProfile,
) {
    fun payload(
        status: String,
        filamentInitialized: Boolean,
        modelPrewarmed: Boolean? = null,
    ): Map<String, Any?> =
        mapOf(
            "status" to status,
            "eligible" to (eligible && filamentInitialized),
            "reasons" to reasons,
            "apiLevel" to profile.apiLevel,
            "minimumApiLevel" to KundiNativeAvatarEligibility.minimumApiLevel,
            "supportedAbis" to profile.supportedAbis,
            "requiredAbi" to KundiNativeAvatarEligibility.requiredAbi,
            "isLowRamDevice" to profile.isLowRamDevice,
            "memoryClassMb" to profile.memoryClassMb,
            // Deliberately unset until measurements exist for both target device classes.
            "minimumMemoryClassMb" to null,
            "requiredGlEsVersion" to profile.requiredGlEsVersion,
            "minimumGlEsVersion" to KundiNativeAvatarEligibility.minimumGlEsVersion,
            "filamentInitialized" to filamentInitialized,
            "modelPrewarmed" to modelPrewarmed,
        )
}

internal object KundiNativeAvatarEligibility {
    const val minimumApiLevel = 29
    const val requiredAbi = "arm64-v8a"
    const val minimumGlEsVersion = 0x00030000

    fun inspect(context: Context): KundiNativeAvatarEligibilityDecision {
        val activityManager =
            checkNotNull(context.getSystemService(ActivityManager::class.java)) {
                "ActivityManager is unavailable"
            }
        return evaluate(
            KundiNativeAvatarDeviceProfile(
                apiLevel = Build.VERSION.SDK_INT,
                supportedAbis = Build.SUPPORTED_ABIS.toList(),
                isLowRamDevice = activityManager.isLowRamDevice,
                memoryClassMb = activityManager.memoryClass,
                requiredGlEsVersion =
                    activityManager.deviceConfigurationInfo.reqGlEsVersion,
            ),
        )
    }

    fun evaluate(
        profile: KundiNativeAvatarDeviceProfile,
    ): KundiNativeAvatarEligibilityDecision {
        val reasons =
            buildList {
                if (profile.apiLevel < minimumApiLevel) add("api_too_old")
                if (requiredAbi !in profile.supportedAbis) add("arm64_unavailable")
                if (profile.isLowRamDevice) add("low_ram_device")
                if (profile.requiredGlEsVersion < minimumGlEsVersion) {
                    add("gles_3_unavailable")
                }
            }
        return KundiNativeAvatarEligibilityDecision(
            eligible = reasons.isEmpty(),
            reasons = reasons,
            profile = profile,
        )
    }
}
