package com.kundi.kundi_mobile.avatar

internal enum class KundiAvatarCadenceMode(
    val wireName: String,
    val targetFps: Int,
) {
    ACTIVE_ANIMATION("activeAnimation", 30),
    PASSIVE_BURST("passiveBurst", 24),
    FROZEN("frozen", 0),
    OFFSCREEN("offscreen", 0),
    BACKGROUND("background", 0),
    DISPOSED("disposed", 0),
}

internal data class KundiAvatarCadenceConfig(
    val passiveBurstIntervalMillis: Long,
    val passiveBurstDurationMillis: Long,
) {
    init {
        require(passiveBurstIntervalMillis in 10_000L..20_000L) {
            "Passive burst interval must be between 10000 and 20000 ms"
        }
        require(passiveBurstDurationMillis in 300L..1_500L) {
            "Passive burst duration must be between 300 and 1500 ms"
        }
    }
}

internal interface KundiAvatarCadenceScheduler {
    fun schedule(
        delayMillis: Long,
        task: Runnable,
    )

    fun cancel(task: Runnable)
}

/**
 * Owns cadence state without depending on Filament or Android lifecycle classes.
 * This keeps timing deterministic in JVM tests and makes zero-frame states explicit.
 */
internal class KundiAvatarCadenceController(
    private val config: KundiAvatarCadenceConfig,
    private val scheduler: KundiAvatarCadenceScheduler,
    private val onPassiveBurstRequested: () -> Unit,
    private val onModeChanged: (KundiAvatarCadenceMode) -> Unit,
) {
    var mode: KundiAvatarCadenceMode = KundiAvatarCadenceMode.OFFSCREEN
        private set

    private var desiredMode = KundiAvatarCadenceMode.FROZEN
    private var attached = false
    private var visible = true
    private var hostResumed = true
    private var disposed = false
    private var passiveStartScheduled = false
    private var passiveEndScheduled = false
    private var passiveBurstsEnabled = false

    private val startPassiveBurst =
        Runnable {
            passiveStartScheduled = false
            if (!canRender() || desiredMode != KundiAvatarCadenceMode.FROZEN) return@Runnable
            desiredMode = KundiAvatarCadenceMode.PASSIVE_BURST
            onPassiveBurstRequested()
            applyMode()
        }

    private val endPassiveBurst =
        Runnable {
            passiveEndScheduled = false
            if (desiredMode != KundiAvatarCadenceMode.PASSIVE_BURST) return@Runnable
            desiredMode = KundiAvatarCadenceMode.FROZEN
            applyMode()
        }

    val targetFps: Int
        get() = mode.targetFps

    val pendingTimerCount: Int
        get() = listOf(passiveStartScheduled, passiveEndScheduled).count { it }

    fun setAttached(value: Boolean) {
        if (disposed || attached == value) return
        attached = value
        applyMode()
    }

    fun setVisible(value: Boolean) {
        if (disposed || visible == value) return
        visible = value
        applyMode()
    }

    fun setHostResumed(value: Boolean) {
        if (disposed || hostResumed == value) return
        hostResumed = value
        applyMode()
    }

    fun startActiveAnimation() {
        if (disposed) return
        passiveBurstsEnabled = false
        desiredMode = KundiAvatarCadenceMode.ACTIVE_ANIMATION
        applyMode()
    }

    fun startPassiveBurst() {
        if (disposed) return
        passiveBurstsEnabled = false
        desiredMode = KundiAvatarCadenceMode.PASSIVE_BURST
        applyMode()
    }

    fun onModelReady(presentationPrimingRequested: Boolean) {
        if (presentationPrimingRequested) {
            startActiveAnimation()
        } else {
            freeze()
        }
    }

    fun freeze(allowPassiveBursts: Boolean = false) {
        if (disposed) return
        passiveBurstsEnabled = allowPassiveBursts
        desiredMode = KundiAvatarCadenceMode.FROZEN
        applyMode()
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        cancelTimers()
        transitionTo(KundiAvatarCadenceMode.DISPOSED)
    }

    private fun applyMode() {
        cancelTimers()
        val nextMode =
            when {
                disposed -> KundiAvatarCadenceMode.DISPOSED
                !hostResumed -> KundiAvatarCadenceMode.BACKGROUND
                !attached || !visible -> KundiAvatarCadenceMode.OFFSCREEN
                else -> desiredMode
            }
        transitionTo(nextMode)
        when (nextMode) {
            KundiAvatarCadenceMode.PASSIVE_BURST -> schedulePassiveEnd()
            KundiAvatarCadenceMode.FROZEN -> {
                if (passiveBurstsEnabled) schedulePassiveStart()
            }
            else -> Unit
        }
    }

    private fun canRender(): Boolean =
        !disposed && attached && visible && hostResumed

    private fun transitionTo(nextMode: KundiAvatarCadenceMode) {
        if (mode == nextMode) return
        mode = nextMode
        onModeChanged(nextMode)
    }

    private fun schedulePassiveStart() {
        if (passiveStartScheduled || !canRender()) return
        passiveStartScheduled = true
        scheduler.schedule(config.passiveBurstIntervalMillis, startPassiveBurst)
    }

    private fun schedulePassiveEnd() {
        if (passiveEndScheduled || !canRender()) return
        passiveEndScheduled = true
        scheduler.schedule(config.passiveBurstDurationMillis, endPassiveBurst)
    }

    private fun cancelTimers() {
        if (passiveStartScheduled) {
            scheduler.cancel(startPassiveBurst)
            passiveStartScheduled = false
        }
        if (passiveEndScheduled) {
            scheduler.cancel(endPassiveBurst)
            passiveEndScheduled = false
        }
    }
}

internal enum class KundiAvatarFrameDirective {
    STOP,
    THROTTLE,
    RENDER_CADENCED,
    RENDER_ONE_SHOT,
}

/**
 * Re-evaluates frame-loop work from the latest cadence snapshot.
 *
 * Cadence may change while a Choreographer callback is running, so callers must
 * ask for a directive after every phase that can freeze or wake the renderer.
 */
internal class KundiAvatarFrameLoopGuard {
    private var nextRenderDeadlineNanos = 0L
    private var fatalError = false

    val hasFatalError: Boolean
        get() = fatalError

    fun evaluate(
        frameTimeNanos: Long,
        targetFps: Int,
        oneShotPending: Boolean,
    ): KundiAvatarFrameDirective {
        require(targetFps >= 0) { "Target FPS must not be negative" }
        if (fatalError) return KundiAvatarFrameDirective.STOP
        if (oneShotPending) return KundiAvatarFrameDirective.RENDER_ONE_SHOT
        if (targetFps == 0) return KundiAvatarFrameDirective.STOP
        return if (shouldThrottleFrame(frameTimeNanos, targetFps)) {
            KundiAvatarFrameDirective.THROTTLE
        } else {
            KundiAvatarFrameDirective.RENDER_CADENCED
        }
    }

    fun canSchedule(
        targetFps: Int,
        oneShotPending: Boolean,
    ): Boolean =
        !fatalError && (targetFps > 0 || oneShotPending)

    fun shouldThrottleFrame(
        frameTimeNanos: Long,
        targetFps: Int,
    ): Boolean {
        check(targetFps > 0) { "A zero-FPS cadence must not receive frame callbacks" }
        val intervalNanos = 1_000_000_000L / targetFps
        if (nextRenderDeadlineNanos == 0L) {
            nextRenderDeadlineNanos = frameTimeNanos + intervalNanos
            return false
        }
        if (frameTimeNanos < nextRenderDeadlineNanos) {
            return true
        }
        do {
            nextRenderDeadlineNanos += intervalNanos
        } while (nextRenderDeadlineNanos <= frameTimeNanos)
        return false
    }

    fun resetCadenceDeadline() {
        nextRenderDeadlineNanos = 0L
    }

    fun markFatalError(): Boolean {
        if (fatalError) return false
        fatalError = true
        resetCadenceDeadline()
        return true
    }
}
