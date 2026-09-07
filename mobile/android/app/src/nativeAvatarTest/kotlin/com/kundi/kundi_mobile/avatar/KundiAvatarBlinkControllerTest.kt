package com.kundi.kundi_mobile.avatar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class KundiAvatarBlinkControllerTest {
    @Test
    fun `blink timer exists only while avatar is visible attached resumed and ready`() {
        val scheduler = FakeBlinkScheduler()
        var blinks = 0
        val controller =
            KundiAvatarBlinkController(
                scheduler = scheduler,
                onBlinkRequested = { blinks++ },
                nextDelayMillis = { 5_200L },
            )

        controller.setAttached(true)
        controller.setModelReady(true)
        assertEquals(5_200L, scheduler.delayMillis)
        assertEquals(1, controller.pendingTimerCount)

        scheduler.runPending()
        assertEquals(1, blinks)
        assertEquals(1, controller.pendingTimerCount)

        controller.setVisible(false)
        assertNull(scheduler.pending)
        assertEquals(0, controller.pendingTimerCount)
        controller.setVisible(true)
        controller.setHostResumed(false)
        assertNull(scheduler.pending)
        controller.setHostResumed(true)
        assertEquals(1, controller.pendingTimerCount)

        controller.dispose()
        controller.dispose()
        assertNull(scheduler.pending)
        assertEquals(0, controller.pendingTimerCount)
    }

    @Test
    fun `natural blink delay is clamped to product bounds`() {
        val scheduler = FakeBlinkScheduler()
        val controller =
            KundiAvatarBlinkController(
                scheduler = scheduler,
                onBlinkRequested = {},
                nextDelayMillis = { Long.MAX_VALUE },
            )
        controller.setAttached(true)
        controller.setModelReady(true)

        assertEquals(7_500L, scheduler.delayMillis)
        controller.dispose()
    }
}

private class FakeBlinkScheduler : KundiAvatarBlinkScheduler {
    var pending: Runnable? = null
    var delayMillis: Long? = null

    override fun schedule(
        delayMillis: Long,
        task: Runnable,
    ) {
        check(pending == null) { "Only one blink timer may be active" }
        this.delayMillis = delayMillis
        pending = task
    }

    override fun cancel(task: Runnable) {
        if (pending === task) {
            pending = null
            delayMillis = null
        }
    }

    fun runPending() {
        val task = checkNotNull(pending)
        pending = null
        delayMillis = null
        task.run()
    }
}
