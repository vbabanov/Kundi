package com.kundi.kundi_mobile.avatar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class KundiAvatarCadenceControllerTest {
    @Test
    fun `active animation is 30 FPS and freeze is zero FPS`() {
        val fixture = CadenceFixture()

        fixture.controller.setAttached(true)
        assertEquals(KundiAvatarCadenceMode.FROZEN, fixture.controller.mode)
        assertEquals(0, fixture.controller.targetFps)

        fixture.controller.startActiveAnimation()
        assertEquals(KundiAvatarCadenceMode.ACTIVE_ANIMATION, fixture.controller.mode)
        assertEquals(30, fixture.controller.targetFps)

        fixture.controller.freeze()
        assertEquals(KundiAvatarCadenceMode.FROZEN, fixture.controller.mode)
        assertEquals(0, fixture.controller.targetFps)
    }

    @Test
    fun `cadence changing from 30 to zero inside a callback stops without throttling`() {
        val frameLoop = KundiAvatarFrameLoopGuard()

        assertEquals(
            KundiAvatarFrameDirective.RENDER_CADENCED,
            frameLoop.evaluate(
                frameTimeNanos = 1_000_000_000L,
                targetFps = 30,
                oneShotPending = false,
            ),
        )
        assertEquals(
            KundiAvatarFrameDirective.STOP,
            frameLoop.evaluate(
                frameTimeNanos = 1_016_000_000L,
                targetFps = 0,
                oneShotPending = false,
            ),
        )
        assertFalse(frameLoop.canSchedule(targetFps = 0, oneShotPending = false))
    }

    @Test
    fun `direct zero FPS throttle call preserves invariant`() {
        val frameLoop = KundiAvatarFrameLoopGuard()

        assertThrows(IllegalStateException::class.java) {
            frameLoop.shouldThrottleFrame(
                frameTimeNanos = 1_000_000_000L,
                targetFps = 0,
            )
        }
    }

    @Test
    fun `model completion with requested priming remains on positive cadence`() {
        val fixture = CadenceFixture()
        fixture.controller.setAttached(true)
        fixture.controller.startActiveAnimation()
        fixture.modes.clear()

        fixture.controller.onModelReady(presentationPrimingRequested = true)

        assertEquals(KundiAvatarCadenceMode.ACTIVE_ANIMATION, fixture.controller.mode)
        assertEquals(30, fixture.controller.targetFps)
        assertTrue(fixture.modes.isEmpty())
    }

    @Test
    fun `model completion before priming freezes and a later request wakes renderer`() {
        val fixture = CadenceFixture()
        fixture.controller.setAttached(true)
        fixture.controller.startActiveAnimation()

        fixture.controller.onModelReady(presentationPrimingRequested = false)
        assertEquals(KundiAvatarCadenceMode.FROZEN, fixture.controller.mode)
        assertEquals(0, fixture.controller.targetFps)

        fixture.controller.startActiveAnimation()
        assertEquals(KundiAvatarCadenceMode.ACTIVE_ANIMATION, fixture.controller.mode)
        assertEquals(30, fixture.controller.targetFps)
    }

    @Test
    fun `one-shot final frame renders once and then returns to zero FPS`() {
        val frameLoop = KundiAvatarFrameLoopGuard()

        assertEquals(
            KundiAvatarFrameDirective.RENDER_ONE_SHOT,
            frameLoop.evaluate(
                frameTimeNanos = 1_000_000_000L,
                targetFps = 0,
                oneShotPending = true,
            ),
        )
        assertEquals(
            KundiAvatarFrameDirective.STOP,
            frameLoop.evaluate(
                frameTimeNanos = 1_016_000_000L,
                targetFps = 0,
                oneShotPending = false,
            ),
        )
    }

    @Test
    fun `fatal frame error is latched once and suppresses future callbacks`() {
        val frameLoop = KundiAvatarFrameLoopGuard()

        assertTrue(frameLoop.markFatalError())
        assertFalse(frameLoop.markFatalError())
        assertEquals(
            KundiAvatarFrameDirective.STOP,
            frameLoop.evaluate(
                frameTimeNanos = 1_000_000_000L,
                targetFps = 30,
                oneShotPending = false,
            ),
        )
        assertFalse(frameLoop.canSchedule(targetFps = 30, oneShotPending = true))
    }

    @Test
    fun `passive burst cadence is bounded and deterministic`() {
        val fixture = CadenceFixture()

        fixture.controller.setAttached(true)
        fixture.controller.freeze(allowPassiveBursts = true)
        assertEquals(15_000L, fixture.scheduler.delayMillis)
        fixture.scheduler.runPending()

        assertEquals(1, fixture.passiveBurstRequests)
        assertEquals(KundiAvatarCadenceMode.PASSIVE_BURST, fixture.controller.mode)
        assertEquals(24, fixture.controller.targetFps)
        assertEquals(800L, fixture.scheduler.delayMillis)

        fixture.scheduler.runPending()
        assertEquals(KundiAvatarCadenceMode.FROZEN, fixture.controller.mode)
        assertEquals(0, fixture.controller.targetFps)
        assertEquals(15_000L, fixture.scheduler.delayMillis)
    }

    @Test
    fun `offscreen and background cancel callbacks and resume prior intent`() {
        val fixture = CadenceFixture()

        fixture.controller.setAttached(true)
        fixture.controller.startActiveAnimation()
        fixture.controller.setVisible(false)
        assertEquals(KundiAvatarCadenceMode.OFFSCREEN, fixture.controller.mode)
        assertEquals(0, fixture.controller.targetFps)
        assertEquals(0, fixture.controller.pendingTimerCount)

        fixture.controller.setVisible(true)
        assertEquals(KundiAvatarCadenceMode.ACTIVE_ANIMATION, fixture.controller.mode)
        fixture.controller.setHostResumed(false)
        assertEquals(KundiAvatarCadenceMode.BACKGROUND, fixture.controller.mode)
        assertEquals(0, fixture.controller.targetFps)

        fixture.controller.freeze(allowPassiveBursts = true)
        fixture.controller.setHostResumed(true)
        assertEquals(KundiAvatarCadenceMode.FROZEN, fixture.controller.mode)
        assertEquals(15_000L, fixture.scheduler.delayMillis)
    }

    @Test
    fun `default Standing freeze schedules no passive Idle bursts`() {
        val fixture = CadenceFixture()

        fixture.controller.setAttached(true)
        fixture.controller.freeze()

        assertEquals(KundiAvatarCadenceMode.FROZEN, fixture.controller.mode)
        assertEquals(0, fixture.controller.pendingTimerCount)
        assertEquals(null, fixture.scheduler.pending)
    }

    @Test
    fun `dispose is terminal and leaves no timers`() {
        val fixture = CadenceFixture()

        fixture.controller.setAttached(true)
        fixture.controller.dispose()
        fixture.controller.startActiveAnimation()
        fixture.controller.setVisible(false)

        assertEquals(KundiAvatarCadenceMode.DISPOSED, fixture.controller.mode)
        assertEquals(0, fixture.controller.targetFps)
        assertEquals(0, fixture.controller.pendingTimerCount)
        assertEquals(null, fixture.scheduler.pending)
    }

    @Test
    fun `passive timing rejects values outside product bounds`() {
        assertThrows(IllegalArgumentException::class.java) {
            KundiAvatarCadenceConfig(9_999L, 800L)
        }
        assertThrows(IllegalArgumentException::class.java) {
            KundiAvatarCadenceConfig(15_000L, 1_501L)
        }
    }
}

private class CadenceFixture {
    val scheduler = FakeCadenceScheduler()
    var passiveBurstRequests = 0
    val modes = mutableListOf<KundiAvatarCadenceMode>()
    val controller =
        KundiAvatarCadenceController(
            config = KundiAvatarCadenceConfig(15_000L, 800L),
            scheduler = scheduler,
            onPassiveBurstRequested = { passiveBurstRequests++ },
            onModeChanged = modes::add,
        )
}

private class FakeCadenceScheduler : KundiAvatarCadenceScheduler {
    var pending: Runnable? = null
    var delayMillis: Long? = null

    override fun schedule(
        delayMillis: Long,
        task: Runnable,
    ) {
        check(pending == null) { "Only one cadence timer may be active" }
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
