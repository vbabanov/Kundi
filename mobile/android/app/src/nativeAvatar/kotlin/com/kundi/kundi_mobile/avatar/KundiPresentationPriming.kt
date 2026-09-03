package com.kundi.kundi_mobile.avatar

internal data class KundiPresentationPrimingConfig(
    val minimumSubmittedFrames: Int,
    val minimumDurationMillis: Long,
    val timeoutMillis: Long,
) {
    init {
        require(minimumSubmittedFrames > 0) { "Priming frame count must be positive" }
        require(minimumDurationMillis > 0L) { "Priming duration must be positive" }
        require(timeoutMillis > minimumDurationMillis) {
            "Priming timeout must exceed its minimum duration"
        }
    }
}

internal object KundiPresentationPrimingDefaults {
    const val presentationPrimeMinFrames = 18
    const val presentationPrimeMinDurationMillis = 700L
    const val presentationPrimeTimeoutMillis = 1_500L

    val config =
        KundiPresentationPrimingConfig(
            minimumSubmittedFrames = presentationPrimeMinFrames,
            minimumDurationMillis = presentationPrimeMinDurationMillis,
            timeoutMillis = presentationPrimeTimeoutMillis,
        )
}

internal data class KundiPresentationPrimingRequest(
    val rendererGeneration: Int,
    val textureId: Long,
    val surfaceGeneration: Int,
    val requestedAtMillis: Long,
)

internal data class KundiPresentationPrimed(
    val request: KundiPresentationPrimingRequest,
    val submittedFrameCount: Int,
    val elapsedMillis: Long,
)

internal data class KundiPresentationPrimingTimedOut(
    val request: KundiPresentationPrimingRequest,
    val submittedFrameCount: Int,
    val elapsedMillis: Long,
)

/** Counts only successful Filament submissions after Flutter requests priming. */
internal class KundiPresentationPrimingTracker(
    private val config: KundiPresentationPrimingConfig =
        KundiPresentationPrimingDefaults.config,
) {
    private var active: ActivePriming? = null
    private var completedKey: Pair<Int, Int>? = null

    val isActive: Boolean
        get() = active != null

    fun begin(request: KundiPresentationPrimingRequest): Boolean {
        require(request.rendererGeneration >= 0) { "Renderer generation must not be negative" }
        require(request.textureId >= 0L) { "Texture ID must not be negative" }
        require(request.surfaceGeneration > 0) { "Surface generation must be positive" }
        val key = request.rendererGeneration to request.surfaceGeneration
        if (completedKey == key) return false
        active = ActivePriming(request = request)
        return true
    }

    fun onFrameSubmitted(nowMillis: Long): KundiPresentationPrimed? {
        val state = active ?: return null
        if (state.firstSubmittedAtMillis == null) {
            state.firstSubmittedAtMillis = nowMillis
        }
        state.submittedFrameCount++
        val elapsed = (nowMillis - checkNotNull(state.firstSubmittedAtMillis)).coerceAtLeast(0L)
        if (
            state.submittedFrameCount < config.minimumSubmittedFrames ||
                elapsed < config.minimumDurationMillis
        ) {
            return null
        }
        active = null
        completedKey = state.request.rendererGeneration to state.request.surfaceGeneration
        return KundiPresentationPrimed(
            request = state.request,
            submittedFrameCount = state.submittedFrameCount,
            elapsedMillis = elapsed,
        )
    }

    fun onTimeout(nowMillis: Long): KundiPresentationPrimingTimedOut? {
        val state = active ?: return null
        val requestedElapsed = (nowMillis - state.request.requestedAtMillis).coerceAtLeast(0L)
        if (requestedElapsed < config.timeoutMillis) return null
        active = null
        val primingElapsed =
            state.firstSubmittedAtMillis?.let { first ->
                (nowMillis - first).coerceAtLeast(0L)
            } ?: 0L
        return KundiPresentationPrimingTimedOut(
            request = state.request,
            submittedFrameCount = state.submittedFrameCount,
            elapsedMillis = primingElapsed,
        )
    }

    fun reset(): Boolean {
        val changed = active != null
        active = null
        return changed
    }

    private data class ActivePriming(
        val request: KundiPresentationPrimingRequest,
        var firstSubmittedAtMillis: Long? = null,
        var submittedFrameCount: Int = 0,
    )
}
