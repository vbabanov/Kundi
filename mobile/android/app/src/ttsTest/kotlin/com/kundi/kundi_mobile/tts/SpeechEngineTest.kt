package com.kundi.kundi_mobile.tts

import org.junit.Assert.*
import org.junit.Test

class SpeechEngineTest {
    private class FakeSynth : Synthesizer {
        lateinit var ready: (SpeechPackage) -> Unit
        lateinit var event: (String) -> Unit
        lateinit var error: (String) -> Unit
        var starts = 0
        var cancelled = 0
        var disposed = false
        var accept = true

        override fun start(
            request: SpeechRequest,
            event: (String) -> Unit,
            ready: (SpeechPackage) -> Unit,
            error: (String) -> Unit,
        ): Boolean {
            starts++
            this.ready = ready
            this.event = event
            this.error = error
            return accept
        }

        override fun cancel() {
            cancelled++
        }

        override fun dispose() {
            disposed = true
        }
    }

    private class FakePlayer : PcmPlayer {
        var focus = true
        var released = 0
        var frames = 0

        override fun start(pcm: ByteArray) = focus

        override fun pump() {}

        override val positionMs
            get() = frames.toLong() * 1000 / 24000

        override val completed
            get() = frames >= 24000

        override fun pause() {}

        override fun release() {
            released++
        }
    }

    private fun request(id: Long = 1) =
        SpeechRequest(
            id,
            "Привет!",
            "fake-token",
            600000,
            "westus",
            "ru-RU",
            "ru-RU-SvetlanaNeural",
        )

    private fun audio() =
        SpeechPackage(
            ByteArray(48000) { 1 },
            listOf(AzureViseme(1, 100), AzureViseme(6, 200)),
            emptyList(),
            "ru-RU",
            "voice",
        )

    @Test
    fun synthesisThenActualHeadThenCompletionReleasesBuffers() {
        val synth = FakeSynth()
        val player = FakePlayer()
        val events = mutableListOf<String>()
        val engine = SpeechEngine(synth, { player }, { _, name, _ -> events.add(name) }, { 0 })
        assertTrue(engine.start(request()))
        synth.event("synthesisStarted")
        val pcm = audio()
        synth.ready(pcm)
        assertEquals(listOf("synthesisStarted", "synthesisReady", "playbackStarted"), events)
        engine.tick()
        assertFalse(events.contains("visemeDue"))
        player.frames = 3000
        engine.tick()
        assertEquals("visemeDue", events.last())
        player.frames = 24000
        engine.tick()
        assertEquals("playbackCompleted", events.last())
        assertEquals(1, player.released)
        assertTrue(pcm.pcm.all { it == 0.toByte() })
        val size = events.size
        engine.tick()
        assertEquals(size, events.size)
    }

    @Test
    fun cancelBargeInAndDisposeSuppressOldCallbacks() {
        val synth = FakeSynth()
        val player = FakePlayer()
        val events = mutableListOf<Pair<Long, String>>()
        val engine =
            SpeechEngine(synth, { player }, { id, name, _ -> events.add(id to name) }, { 0 })
        engine.start(request())
        val late = synth.ready
        engine.cancel()
        engine.start(request(2))
        val pcm = audio()
        late(pcm)
        assertTrue(pcm.pcm.all { it == 0.toByte() })
        assertFalse(events.any { it.first == 1L && it.second == "playbackStarted" })
        assertFalse(engine.start(request(2)))
        engine.dispose()
        engine.dispose()
        val size = events.size
        synth.event("synthesisStarted")
        synth.ready(audio())
        synth.error("failed")
        assertEquals(size, events.size)
        assertTrue(synth.disposed)
    }

    @Test
    fun cancellationDuringPlaybackReleasesFocusAndPendingTimelineOnce() {
        val synth = FakeSynth()
        val player = FakePlayer()
        val events = mutableListOf<String>()
        val engine = SpeechEngine(synth, { player }, { _, name, _ -> events.add(name) }, { 0 })
        engine.start(request())
        val pcm = audio()
        synth.ready(pcm)
        player.frames = 3000
        engine.tick()
        assertEquals("visemeDue", events.last())
        // The focus-loss and background host paths both call this operation.
        engine.cancel()
        engine.cancel()
        player.frames = 24000
        engine.tick()
        synth.event("synthesisStarted")
        synth.error("late_error")
        assertEquals("playbackCancelled", events.last())
        assertEquals(1, events.count { it == "playbackCancelled" })
        assertEquals(1, player.released)
        assertTrue(pcm.pcm.all { it == 0.toByte() })
        assertFalse(engine.active)
    }

    @Test
    fun tokenExpiryBusyAndFocusDenialAreTerminal() {
        val synth = FakeSynth()
        val player = FakePlayer()
        val codes = mutableListOf<String>()
        val engine =
            SpeechEngine(
                synth,
                { player },
                { _, name, data -> if (name == "speechError") codes.add(data["code"] as String) },
                { 0 },
            )
        assertFalse(engine.start(request().copy(expiresAtMs = 59999)))
        assertEquals(0, synth.starts)
        synth.accept = false
        assertFalse(engine.start(request(2)))
        synth.accept = true
        player.focus = false
        engine.start(request(3))
        synth.ready(audio())
        assertEquals(listOf("token_expired", "synthesis_busy", "audio_focus"), codes)
        assertEquals(1, player.released)
    }
}
