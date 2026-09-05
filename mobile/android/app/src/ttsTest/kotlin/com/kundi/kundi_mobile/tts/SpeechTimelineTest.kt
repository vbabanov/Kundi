package com.kundi.kundi_mobile.tts

import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.*
import org.junit.Test

class SpeechTimelineTest {
    @Test
    fun endpointScopeMustMatchTokenOrigin() {
        assertTrue(
            SpeechEndpoint.isRegional("https://westus.api.cognitive.microsoft.com", "westus")
        )
        assertFalse(
            SpeechEndpoint.isRegional(
                "https://example-resource.cognitiveservices.azure.com/",
                "westus",
            )
        )
        assertEquals(
            "wss://example-resource.cognitiveservices.azure.com",
            SpeechEndpoint.websocket("https://example-resource.cognitiveservices.azure.com/")
                .toString(),
        )
        for (origin in
            listOf(
                "https://attacker.invalid",
                "http://westus.api.cognitive.microsoft.com",
                "https://eastus.api.cognitive.microsoft.com",
                "https://westus.api.cognitive.microsoft.com/?key=value",
            )) {
            assertThrows(IllegalArgumentException::class.java) {
                SpeechEndpoint.isRegional(origin, "westus")
            }
        }
    }

    @Test
    fun russianVowelsAndConsonants() {
        val expected =
            listOf(
                Mouth.Neutral,
                Mouth.A,
                Mouth.A,
                Mouth.O,
                Mouth.E,
                Mouth.E,
                Mouth.I,
                Mouth.U,
                Mouth.O,
                Mouth.A,
                Mouth.O,
                Mouth.A,
            )
        expected.forEachIndexed { id, mouth -> assertEquals(mouth, SpeechTimeline.ruVowels[id]) }
        val timeline =
            SpeechTimeline.azure(
                listOf(
                    AzureViseme(1, 0),
                    AzureViseme(12, 100),
                    AzureViseme(7, 200),
                    AzureViseme(21, 300),
                ),
                500,
            )
        assertTrue(timeline.contains(MouthEvent(180, Mouth.Neutral)))
        assertTrue(timeline.contains(MouthEvent(300, Mouth.Neutral)))
        for (id in 12..21) assertTrue(
            SpeechTimeline.azure(listOf(AzureViseme(id, 0)), 100).last().mouth == Mouth.Neutral
        )
    }

    @Test
    fun kazakhWordsUseRealIntervalsAndAllVowels() {
        assertEquals(15, SpeechTimeline.kazakhVowels.size)
        val text = "Сәлем әлем"
        val pcm = ByteArray(48000)
        val audio =
            SpeechPackage(
                pcm,
                listOf(AzureViseme(0, 0)),
                listOf(
                    WordBoundary(100, 300, 0, 5),
                    WordBoundary(600, 300, 6, 4),
                ),
                "kk-KZ",
                "kk-KZ-AigulNeural",
            )
        val events = SpeechTimeline.build(text, audio)
        assertTrue(events.contains(MouthEvent(100, Mouth.A)))
        assertTrue(events.contains(MouthEvent(250, Mouth.E)))
        assertTrue(events.contains(MouthEvent(400, Mouth.Neutral)))
        assertTrue(events.contains(MouthEvent(600, Mouth.A)))
        assertTrue(events.none { it.offsetMs in 401..599 })
    }

    @Test
    fun amplitudeIsDeterministicAndSilenceCloses() {
        val pcm = ByteArray(48000)
        for (i in 6000 until 12000) {
            pcm[i * 2] = 0
            pcm[i * 2 + 1] = 32
        }
        val timeline = SpeechTimeline.amplitude(pcm)
        assertEquals(timeline, SpeechTimeline.amplitude(pcm))
        assertTrue(timeline.any { it.mouth != Mouth.Neutral })
        assertEquals(Mouth.Neutral, timeline.last().mouth)
        assertTrue(timeline.zipWithNext().all { (a, b) -> b.offsetMs - a.offsetMs >= 120 })
        assertTrue(SpeechTimeline.amplitude(ByteArray(48000)).isEmpty())
    }

    @Test
    fun schedulerUsesPlaybackPositionAndSkipsOverdueShapes() {
        val cursor =
            VisemeCursor(
                listOf(MouthEvent(100, Mouth.A), MouthEvent(200, Mouth.I), MouthEvent(300, Mouth.O))
            )
        assertNull(cursor.due(0))
        assertNull(cursor.due(99))
        assertEquals(Mouth.I, cursor.due(250))
        assertNull(cursor.due(250))
        assertEquals(Mouth.O, cursor.due(300))
    }

    @Test
    fun invalidOffsetsAndPcmAreRejected() {
        val audio =
            SpeechPackage(
                ByteArray(48000),
                listOf(AzureViseme(1, 300), AzureViseme(2, 200)),
                emptyList(),
                "ru-RU",
                "voice",
            )
        assertThrows(IllegalArgumentException::class.java) { audio.validate("text") }
        assertThrows(IllegalArgumentException::class.java) {
            audio.copy(pcm = ByteArray(3), visemes = emptyList()).validate("text")
        }
        assertThrows(IllegalArgumentException::class.java) {
            audio
                .copy(visemes = emptyList(), words = listOf(WordBoundary(900, 200, 0, 4)))
                .validate("text")
        }
        assertThrows(IllegalArgumentException::class.java) {
            audio.copy(visemes = listOf(AzureViseme(22, 0))).validate("text")
        }
    }

    @Test
    fun collectorBoundsCancelAndClear() {
        val stop = AtomicBoolean(false)
        val collector = SpeechCollector(stop)
        assertEquals(SpeechLimits.maxPcmBytes, collector.write(ByteArray(SpeechLimits.maxPcmBytes)))
        assertEquals(0, collector.write(ByteArray(2)))
        assertThrows(IllegalStateException::class.java) { collector.finish("ru", "voice") }
        collector.clear()
        val cancelled = SpeechCollector(stop)
        stop.set(true)
        assertEquals(0, cancelled.write(ByteArray(100)))
        assertThrows(IllegalStateException::class.java) { cancelled.finish("ru", "voice") }
        val events = SpeechCollector(AtomicBoolean(false))
        repeat(SpeechLimits.maxEvents + 1) { events.viseme(AzureViseme(0, 0)) }
        assertThrows(IllegalStateException::class.java) { events.finish("ru", "voice") }
    }

    @Test
    fun textTruncatesAtSentenceOrWholeWord() {
        val sentence = "Привет! "
        assertEquals("Привет!", SpeechLimits.spokenText(sentence + "слово ".repeat(300)))
        assertFalse(SpeechLimits.spokenText("слово ".repeat(300)).endsWith("слов"))
        assertThrows(IllegalArgumentException::class.java) {
            SpeechLimits.spokenText("а".repeat(901))
        }
    }
}
