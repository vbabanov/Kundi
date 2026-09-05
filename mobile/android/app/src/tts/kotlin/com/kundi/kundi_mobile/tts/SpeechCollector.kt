package com.kundi.kundi_mobile.tts

import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicBoolean

/** Bounded callback collector, independent of Android and Azure classes for tests. */
internal class SpeechCollector(private val stopping: AtomicBoolean) {
    private val pcm =
        object : ByteArrayOutputStream() {
            fun wipe() {
                buf.fill(0)
                reset()
            }
        }
    private val visemes = mutableListOf<AzureViseme>()
    private val words = mutableListOf<WordBoundary>()
    private var invalid = false
    @Volatile var started = false
    @Volatile var chunks = 0
    @Volatile var completed = false
    @Volatile var cancelled = false

    @Synchronized
    fun write(data: ByteArray): Int {
        if (stopping.get() || invalid) return 0
        if (data.size > SpeechLimits.maxPcmBytes - pcm.size()) {
            invalid = true
            return 0
        }
        pcm.write(data)
        return data.size
    }

    @Synchronized
    fun viseme(value: AzureViseme) {
        if (stopping.get() || invalid) return
        if (visemes.size >= SpeechLimits.maxEvents) invalid = true else visemes.add(value)
    }

    @Synchronized
    fun word(value: WordBoundary) {
        if (stopping.get() || invalid) return
        if (words.size >= SpeechLimits.maxEvents) invalid = true else words.add(value)
    }

    @Synchronized
    fun finish(locale: String, voice: String): SpeechPackage {
        check(!invalid && !cancelled && !stopping.get())
        return SpeechPackage(pcm.toByteArray(), visemes.toList(), words.toList(), locale, voice)
    }

    @Synchronized
    fun clear() {
        pcm.wipe()
        visemes.clear()
        words.clear()
    }
}
