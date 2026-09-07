package com.kundi.kundi_mobile.avatar

import kotlin.random.Random

internal interface KundiAvatarBlinkScheduler {
    fun schedule(
        delayMillis: Long,
        task: Runnable,
    )

    fun cancel(task: Runnable)
}

/** Schedules at most one bounded blink timer while the Home avatar can render. */
internal class KundiAvatarBlinkController(
    private val scheduler: KundiAvatarBlinkScheduler,
    private val onBlinkRequested: () -> Unit,
    private val minIntervalMillis: Long = 3_500L,
    private val maxIntervalMillis: Long = 7_500L,
    private val nextDelayMillis: (() -> Long)? = null,
) {
    private var attached = false
    private var visible = true
    private var hostResumed = true
    private var modelReady = false
    private var disposed = false
    private var scheduled = false

    private val blinkTask =
        Runnable {
            scheduled = false
            if (!eligible()) return@Runnable
            onBlinkRequested()
            scheduleIfEligible()
        }

    init {
        require(minIntervalMillis > 0L && maxIntervalMillis >= minIntervalMillis) {
            "Blink interval bounds are invalid"
        }
    }

    val pendingTimerCount: Int
        get() = if (scheduled) 1 else 0

    fun setAttached(value: Boolean) {
        if (disposed || attached == value) return
        attached = value
        refresh()
    }

    fun setVisible(value: Boolean) {
        if (disposed || visible == value) return
        visible = value
        refresh()
    }

    fun setHostResumed(value: Boolean) {
        if (disposed || hostResumed == value) return
        hostResumed = value
        refresh()
    }

    fun setModelReady(value: Boolean) {
        if (disposed || modelReady == value) return
        modelReady = value
        refresh()
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        cancel()
    }

    private fun refresh() {
        if (eligible()) scheduleIfEligible() else cancel()
    }

    private fun eligible(): Boolean =
        !disposed && attached && visible && hostResumed && modelReady

    private fun scheduleIfEligible() {
        if (!eligible() || scheduled) return
        val delay =
            (nextDelayMillis?.invoke()
                ?: Random.Default.nextLong(minIntervalMillis, maxIntervalMillis + 1))
                .coerceIn(minIntervalMillis, maxIntervalMillis)
        scheduled = true
        scheduler.schedule(delay, blinkTask)
    }

    private fun cancel() {
        if (!scheduled) return
        scheduler.cancel(blinkTask)
        scheduled = false
    }
}
