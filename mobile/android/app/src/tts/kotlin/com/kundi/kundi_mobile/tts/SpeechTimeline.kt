package com.kundi.kundi_mobile.tts

import kotlin.math.sqrt

object SpeechLimits {
    const val sampleRate = 24000
    const val maxSpokenChars = 900
    const val maxContentChars = 32000 // UTF-16, backend limit is 16000 runes.
    const val maxDurationMs = 90000L
    const val maxPcmBytes = 4320000
    const val maxEvents = 4096
    const val synthesisTimeoutSeconds = 30L
    const val tokenMarginMs = 60000L
    const val usableVisemeRatio = 0.08
    const val consonantDecayMs = 80L
    const val amplitudeWindowMs = 120L
    const val silenceRms = 0.018

    fun spokenText(text: String): String {
        require(text.isNotBlank() && text.length <= maxContentChars)
        if (text.length <= maxSpokenChars) return text
        val prefix = text.take(maxSpokenChars)
        val sentence = Regex("[.!?…](?:\\s|$)").findAll(prefix).lastOrNull()
        val end = sentence?.let { it.range.first + 1 } ?: prefix.indexOfLast { it.isWhitespace() }
        require(end > 0) // Never cut a single overlong word.
        return prefix.take(end).trimEnd()
    }
}

enum class Mouth {
    Neutral,
    A,
    I,
    U,
    E,
    O,
}

data class AzureViseme(val id: Int, val offsetMs: Long)

data class WordBoundary(
    val offsetMs: Long,
    val durationMs: Long,
    val position: Int,
    val length: Int,
)

data class MouthEvent(val offsetMs: Long, val mouth: Mouth)

data class SpeechPackage(
    val pcm: ByteArray,
    val visemes: List<AzureViseme>,
    val words: List<WordBoundary>,
    val locale: String,
    val voice: String,
) {
    val sampleRate = SpeechLimits.sampleRate
    val durationMs: Long
        get() = pcm.size.toLong() * 1000 / (sampleRate * 2)

    fun validate(text: String) {
        require(pcm.isNotEmpty() && pcm.size % 2 == 0 && pcm.size <= SpeechLimits.maxPcmBytes)
        require(durationMs in 1..SpeechLimits.maxDurationMs)
        require(visemes.size <= SpeechLimits.maxEvents && words.size <= SpeechLimits.maxEvents)
        require(visemes.zipWithNext().all { (a, b) -> a.offsetMs <= b.offsetMs })
        require(words.zipWithNext().all { (a, b) -> a.offsetMs <= b.offsetMs })
        require(visemes.all { it.id in 0..21 && it.offsetMs in 0..durationMs })
        require(
            words.all {
                it.offsetMs in 0..durationMs &&
                    it.durationMs >= 0 &&
                    it.durationMs <= durationMs - it.offsetMs &&
                    it.position >= 0 &&
                    it.length > 0 &&
                    it.position <= text.length - it.length
            }
        )
    }
}

/** Renderer-neutral initial table. Consonants decay; 21 (p/b/m) closes at once. */
object SpeechTimeline {
    val ruVowels =
        mapOf(
            0 to Mouth.Neutral,
            1 to Mouth.A,
            2 to Mouth.A,
            9 to Mouth.A,
            11 to Mouth.A,
            3 to Mouth.O,
            8 to Mouth.O,
            10 to Mouth.O,
            4 to Mouth.E,
            5 to Mouth.E,
            6 to Mouth.I,
            7 to Mouth.U,
        )
    val kazakhVowels =
        mapOf(
            'а' to Mouth.A,
            'ә' to Mouth.A,
            'е' to Mouth.E,
            'ё' to Mouth.O,
            'и' to Mouth.I,
            'і' to Mouth.I,
            'о' to Mouth.O,
            'ө' to Mouth.O,
            'ұ' to Mouth.U,
            'ү' to Mouth.U,
            'у' to Mouth.U,
            'ы' to Mouth.I,
            'э' to Mouth.E,
            'ю' to Mouth.U,
            'я' to Mouth.A,
        )

    fun build(text: String, audio: SpeechPackage): List<MouthEvent> {
        audio.validate(text)
        val usable =
            audio.visemes.count { it.id != 0 }.toDouble() / audio.visemes.size.coerceAtLeast(1)
        val timeline =
            when {
                usable >= SpeechLimits.usableVisemeRatio -> azure(audio.visemes, audio.durationMs)
                audio.words.isNotEmpty() -> words(text, audio.words, audio.durationMs)
                else -> amplitude(audio.pcm)
            }
        return (listOf(MouthEvent(0, Mouth.Neutral)) +
                timeline +
                MouthEvent(audio.durationMs, Mouth.Neutral))
            .sortedBy { it.offsetMs }
    }

    fun azure(events: List<AzureViseme>, durationMs: Long): List<MouthEvent> {
        var previous = Mouth.Neutral
        return buildList {
            events.forEachIndexed { index, event ->
                val vowel = ruVowels[event.id]
                if (vowel != null || event.id == 21) {
                    previous = vowel ?: Mouth.Neutral
                    add(MouthEvent(event.offsetMs, previous))
                } else {
                    add(MouthEvent(event.offsetMs, previous))
                    val next = events.getOrNull(index + 1)?.offsetMs ?: durationMs
                    add(
                        MouthEvent(
                            (event.offsetMs + SpeechLimits.consonantDecayMs).coerceAtMost(next),
                            Mouth.Neutral,
                        )
                    )
                    previous = Mouth.Neutral
                }
            }
        }
    }

    fun words(text: String, words: List<WordBoundary>, durationMs: Long): List<MouthEvent> =
        buildList {
            words.forEachIndexed { index, word ->
                val next = words.getOrNull(index + 1)?.offsetMs ?: durationMs
                val end =
                    if (word.durationMs > 0) minOf(next, word.offsetMs + word.durationMs) else next
                val vowels =
                    text
                        .substring(word.position, word.position + word.length)
                        .lowercase()
                        .mapNotNull { kazakhVowels[it] }
                if (vowels.isEmpty()) add(MouthEvent(word.offsetMs, Mouth.Neutral))
                else
                    vowels.forEachIndexed { i, mouth ->
                        add(
                            MouthEvent(
                                word.offsetMs + (end - word.offsetMs) * i / vowels.size,
                                mouth,
                            )
                        )
                    }
                add(MouthEvent(end, Mouth.Neutral))
            }
        }

    fun amplitude(pcm: ByteArray): List<MouthEvent> = buildList {
        val samplesPerWindow =
            (SpeechLimits.sampleRate * SpeechLimits.amplitudeWindowMs / 1000).toInt()
        var previous = Mouth.Neutral
        var sample = 0
        while (sample < pcm.size / 2) {
            val end = minOf(sample + samplesPerWindow, pcm.size / 2)
            var energy = 0.0
            for (i in sample until end) {
                val value =
                    ((pcm[2 * i].toInt() and 255) or (pcm[2 * i + 1].toInt() shl 8))
                        .toShort()
                        .toDouble() / 32768
                energy += value * value
            }
            val rms = sqrt(energy / (end - sample))
            val mouth =
                if (rms < SpeechLimits.silenceRms) Mouth.Neutral
                else if ((sample / samplesPerWindow) % 4 < 2) Mouth.A else Mouth.O
            if (mouth != previous)
                add(MouthEvent(sample.toLong() * 1000 / SpeechLimits.sampleRate, mouth))
            previous = mouth
            sample = end
        }
    }
}

/** One cursor driven by actual frames played, never synthesis or wall time. */
class VisemeCursor(private val timeline: List<MouthEvent>) {
    private var index = 0
    private var previous = Mouth.Neutral

    fun due(positionMs: Long): Mouth? {
        var mouth = previous
        while (index < timeline.size && timeline[index].offsetMs <= positionMs) {
            mouth = timeline[index++].mouth
        }
        if (mouth == previous) return null
        previous = mouth
        return mouth
    }
}
