package com.kundi.kundi_mobile.speech

internal object KundiSystemSpeechPolicy {
    const val maximumListeningMillis = 20_000L

    enum class PermissionState { GRANTED, REQUIRED, PERMANENTLY_DENIED }

    fun permissionState(granted: Boolean, previouslyAsked: Boolean, shouldShowRationale: Boolean): PermissionState =
        when {
            granted -> PermissionState.GRANTED
            previouslyAsked && !shouldShowRationale -> PermissionState.PERMANENTLY_DENIED
            else -> PermissionState.REQUIRED
        }

    fun errorCode(androidError: Int): String =
        when (androidError) {
            9 -> "permission_denied"
            7 -> "no_match"
            6 -> "no_speech"
            3 -> "audio_error"
            1, 2 -> "network_error"
            4, 11 -> "server_error"
            8, 10 -> "busy"
            5 -> "cancelled"
            12, 13 -> "unavailable"
            else -> "unknown"
        }

    fun timedOut(startedAtMillis: Long, nowMillis: Long): Boolean =
        nowMillis - startedAtMillis >= maximumListeningMillis

    // Phase 2A always uses the default system recognizer. API 31 capability is
    // reported to Flutter, but never forces an on-device engine or locale.
    fun useOnDeviceRecognizer(apiLevel: Int, onDeviceAvailable: Boolean): Boolean = false
}
