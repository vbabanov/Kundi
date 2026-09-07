package com.kundi.kundi_mobile.avatar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KundiNativeAvatarRendererSessionTest {
    @Test
    fun `Android 10 memory trim handles legacy running UI hidden and intermediate levels`() {
        assertFalse(shouldReleaseAvatarForMemoryLevel(4, apiLevel = 29))
        assertTrue(shouldReleaseAvatarForMemoryLevel(5, apiLevel = 29))
        assertTrue(shouldReleaseAvatarForMemoryLevel(10, apiLevel = 29))
        assertTrue(shouldReleaseAvatarForMemoryLevel(15, apiLevel = 29))
        assertTrue(shouldReleaseAvatarForMemoryLevel(17, apiLevel = 29))
        assertTrue(shouldReleaseAvatarForMemoryLevel(20, apiLevel = 29))
        assertTrue(shouldReleaseAvatarForMemoryLevel(31, apiLevel = 29))
        assertTrue(shouldReleaseAvatarForMemoryLevel(40, apiLevel = 29))
        assertTrue(shouldReleaseAvatarForMemoryLevel(80, apiLevel = 29))
    }

    @Test
    fun `Android 14 ignores retired running levels but releases UI hidden and above`() {
        assertFalse(shouldReleaseAvatarForMemoryLevel(5, apiLevel = 34))
        assertFalse(shouldReleaseAvatarForMemoryLevel(15, apiLevel = 34))
        assertTrue(shouldReleaseAvatarForMemoryLevel(20, apiLevel = 34))
        assertTrue(shouldReleaseAvatarForMemoryLevel(21, apiLevel = 34))
        assertTrue(shouldReleaseAvatarForMemoryLevel(40, apiLevel = 34))
    }

    @Test
    fun `quick return cancels grace destroy and reuses renderer`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.setVisible(false)
        assertEquals(30_000L, fixture.scheduler.delayMillis)
        fixture.session.setVisible(true)

        assertNull(fixture.scheduler.pending)
        assertEquals(1, fixture.renderers.size)
        assertEquals(0, fixture.renderers.single().disposeCount)
        assertEquals(1, fixture.rendererCreateCount())
        assertEquals(1, fixture.modelLoadCount())
    }

    @Test
    fun `grace timeout destroys renderer and next visit recreates it`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.setVisible(false)
        fixture.scheduler.runPending()

        assertEquals(1, fixture.renderers.single().disposeCount)
        assertEquals(1, fixture.clearCacheCount)

        fixture.session.setVisible(true)
        assertEquals(2, fixture.renderers.size)
        assertEquals(2, fixture.rendererCreateCount())
        assertEquals(2, fixture.modelLoadCount())
    }

    @Test
    fun `memory pressure forces dispose and waits for a visibility cycle`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.onMemoryPressure(10)
        fixture.session.setVisible(true)

        assertEquals(1, fixture.renderers.size)
        assertEquals(1, fixture.renderers.single().disposeCount)
        assertTrue(fixture.statuses().contains("memoryPressureFallback"))

        fixture.session.setVisible(false)
        fixture.session.setVisible(true)
        assertEquals(2, fixture.renderers.size)
    }

    @Test
    fun `UI hidden dispose can recreate directly on resume`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.onHostPause()
        fixture.session.onMemoryPressure(
            level = 20,
            blockRecreationUntilHidden = false,
        )
        fixture.session.onHostResume()

        assertEquals(2, fixture.renderers.size)
        assertEquals(1, fixture.renderers.first().disposeCount)
    }

    @Test
    fun `recreated renderer receives the last stable behavior and face state`() {
        val fixture = Fixture()
        val idle =
            NativeAvatarCommand.PlayAnimation(
                animation = "Idle",
                cadence = NativeAvatarAnimationCadence.PASSIVE_BURST,
            )
        val emotion = NativeAvatarCommand.SetEmotion("joy")
        val viseme = NativeAvatarCommand.SetViseme("a")

        fixture.attachAndShow()
        fixture.session.execute(idle)
        fixture.session.execute(emotion)
        fixture.session.execute(viseme)
        fixture.session.execute(NativeAvatarCommand.Blink)
        fixture.session.onHostPause()
        fixture.session.onAppUiHidden()
        fixture.session.onHostResume()

        assertEquals(2, fixture.renderers.size)
        assertEquals(
            listOf(emotion, viseme, idle),
            fixture.renderers.last().commands,
        )
    }

    @Test
    fun `freeze is replayed while transient blink and reset face state are not`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.execute(NativeAvatarCommand.SetEmotion("joy"))
        fixture.session.execute(NativeAvatarCommand.SetViseme("a"))
        fixture.session.execute(NativeAvatarCommand.ResetFace)
        fixture.session.execute(NativeAvatarCommand.Freeze)
        fixture.session.onHostPause()
        fixture.session.onAppUiHidden()
        fixture.session.onHostResume()

        assertEquals(listOf(NativeAvatarCommand.Freeze), fixture.renderers.last().commands)
    }

    @Test
    fun `clear viseme drops retained mouth without dropping retained emotion`() {
        val fixture = Fixture()
        val emotion = NativeAvatarCommand.SetEmotion("Joy", 0.4f)

        fixture.attachAndShow()
        fixture.session.execute(emotion)
        fixture.session.execute(NativeAvatarCommand.SetViseme("A", 0.8f))
        fixture.session.execute(NativeAvatarCommand.ClearViseme)
        fixture.session.onHostPause()
        fixture.session.onAppUiHidden()
        fixture.session.onHostResume()

        assertEquals(listOf(emotion), fixture.renderers.last().commands)
    }

    @Test
    fun `deterministic rest pose is retained as the final animation state`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.execute(NativeAvatarCommand.SetEmotion("joy"))
        fixture.session.execute(NativeAvatarCommand.SettleRestPose)
        fixture.session.onHostPause()
        fixture.session.onAppUiHidden()
        fixture.session.onHostResume()

        assertEquals(
            listOf(
                NativeAvatarCommand.SetEmotion("joy"),
                NativeAvatarCommand.SettleRestPose,
            ),
            fixture.renderers.last().commands,
        )
    }

    @Test
    fun `presentation priming is transient and is not replayed on renderer recreation`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.execute(
            NativeAvatarCommand.StartPresentationPriming(
                rendererGeneration = 1,
                textureId = 42L,
            ),
        )
        fixture.session.execute(NativeAvatarCommand.SettleRestPose)
        fixture.session.onHostPause()
        fixture.session.onAppUiHidden()
        fixture.session.onHostResume()

        assertEquals(
            listOf(NativeAvatarCommand.SettleRestPose),
            fixture.renderers.last().commands,
        )
    }

    @Test
    fun `app UI hidden immediately releases renderer without malloc hacks`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.onHostPause()
        fixture.session.onAppUiHidden()

        assertEquals(1, fixture.renderers.single().disposeCount)
        assertNull(fixture.scheduler.pending)
        assertTrue(fixture.statuses().contains("appUiHidden"))
    }

    @Test
    fun `offscreen immediately disables rendering before grace timeout`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.setVisible(false)

        assertFalse(fixture.renderers.single().visible)
        assertEquals(0, fixture.renderers.single().disposeCount)
        assertTrue(fixture.scheduler.pending != null)
    }

    @Test
    fun `short background reuses renderer and long background disposes it`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.onHostPause()
        fixture.session.onHostResume()
        assertNull(fixture.scheduler.pending)
        assertEquals(1, fixture.renderers.size)

        fixture.session.onHostPause()
        fixture.scheduler.runPending()
        assertEquals(1, fixture.renderers.single().disposeCount)

        fixture.session.onHostResume()
        assertEquals(2, fixture.renderers.size)
    }

    @Test
    fun `terminate is idempotent`() {
        val fixture = Fixture()

        fixture.attachAndShow()
        fixture.session.terminate()
        fixture.session.terminate()

        assertEquals(1, fixture.renderers.single().disposeCount)
        assertEquals(1, fixture.clearCacheCount)
    }
}

private class Fixture {
    val scheduler = FakeScheduler()
    val renderers = mutableListOf<FakeRenderer>()
    val events = mutableListOf<Map<String, Any?>>()
    var clearCacheCount = 0
    val session =
        KundiNativeAvatarRendererSession(
            gracePeriodMillis = 30_000L,
            scheduler = scheduler,
            rendererFactory =
                KundiAvatarRendererFactory {
                    FakeRenderer().also(renderers::add)
                },
            clearModelCache = { clearCacheCount++ },
            emitEvent = events::add,
        )

    fun attachAndShow() {
        session.setAttached(true)
        session.setVisible(true)
    }

    fun statuses(): List<String> =
        events.mapNotNull { event ->
            @Suppress("UNCHECKED_CAST")
            val payload = event["payload"] as? Map<String, Any?>
            payload?.get("status") as? String
        }

    fun rendererCreateCount(): Int = latestCount("rendererCreateCount")

    fun modelLoadCount(): Int = latestCount("modelLoadCount")

    private fun latestCount(name: String): Int {
        val payload = events.last()["payload"] as Map<*, *>
        return (payload[name] as Number).toInt()
    }
}

private class FakeScheduler : KundiAvatarSessionScheduler {
    var pending: Runnable? = null
    var delayMillis: Long? = null

    override fun schedule(
        delayMillis: Long,
        task: Runnable,
    ) {
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
        val task = pending
        pending = null
        delayMillis = null
        task?.run()
    }
}

private class FakeRenderer : KundiAvatarRendererBackend {
    var visible = false
    var disposeCount = 0
    val commands = mutableListOf<NativeAvatarCommand>()

    override fun setAttached(value: Boolean) = Unit

    override fun onHostResume() = Unit

    override fun onHostPause() = Unit

    override fun execute(command: NativeAvatarCommand) {
        commands += command
        if (command is NativeAvatarCommand.SetVisible) {
            visible = command.visible
        }
    }

    override fun dispose() {
        disposeCount++
    }
}
