package com.kundi.kundi_mobile.tts

import android.util.Log
import com.microsoft.cognitiveservices.speech.*
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Official SDK adapter. No key, file output, diagnostic logging, or raw errors. */
class AzureSpeechSynthesizer(private val post: (() -> Unit) -> Unit) : Synthesizer {
    private val executor = ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS, SynchronousQueue())
    private val busy = AtomicBoolean(false)
    @Volatile private var disposed = false
    @Volatile private var job: Job? = null

    private class Job {
        val cancelled = AtomicBoolean(false)
        @Volatile var sdk: SpeechSynthesizer? = null
        @Volatile var collector: SpeechCollector? = null

        fun cancel() {
            cancelled.set(true)
            collector?.clear()
            synchronized(this) { runCatching { sdk?.StopSpeakingAsync() } }
        }
    }

    override fun start(
        request: SpeechRequest,
        event: (String) -> Unit,
        ready: (SpeechPackage) -> Unit,
        error: (String) -> Unit,
    ): Boolean {
        if (disposed || !busy.compareAndSet(false, true)) return false
        val active = Job()
        job = active
        try {
            executor.execute {
                var output: SpeechPackage? = null
                var failed: String? = null
                try {
                    check(!active.cancelled.get())
                    val configuration =
                        if (SpeechEndpoint.isRegional(request.endpoint, request.region)) {
                            SpeechConfig.fromAuthorizationToken(request.token, request.region)
                        } else {
                            SpeechConfig.fromEndpoint(SpeechEndpoint.websocket(request.endpoint))
                                .apply {
                                    setAuthorizationToken(request.token)
                                }
                        }
                    configuration.use { config ->
                        config.setSpeechSynthesisLanguage(request.locale)
                        config.setSpeechSynthesisVoiceName(request.voice)
                        config.setSpeechSynthesisOutputFormat(
                            SpeechSynthesisOutputFormat.Raw24Khz16BitMonoPcm
                        )
                        config.setProperty(
                            PropertyId.SpeechServiceResponse_RequestWordBoundary,
                            "true",
                        )
                        val collector = SpeechCollector(active.cancelled)
                        active.collector = collector
                        try {
                            // A null AudioConfig keeps playback under Kundi's AudioTrack while
                            // exposing PCM through SpeechSynthesisResult.audioData. The SDK push
                            // stream completed with zero bytes on the Redmi Note 7/API 29.
                            SpeechSynthesizer(config, null).use { sdk ->
                                synchronized(active) { active.sdk = sdk }
                                try {
                                    check(!active.cancelled.get())
                                    sdk.SynthesisStarted.addEventListener { _, _ ->
                                        collector.started = true
                                        post {
                                            if (!disposed && !active.cancelled.get())
                                                event("synthesisStarted")
                                        }
                                    }
                                    sdk.Synthesizing.addEventListener { _, _ -> collector.chunks++ }
                                    sdk.SynthesisCompleted.addEventListener { _, _ ->
                                        collector.completed = true
                                    }
                                    sdk.SynthesisCanceled.addEventListener { _, _ ->
                                        collector.cancelled = true
                                    }
                                    sdk.VisemeReceived.addEventListener { _, e ->
                                        collector.viseme(
                                            AzureViseme(
                                                e.visemeId.toInt(),
                                                e.audioOffset / 10000,
                                            )
                                        )
                                    }
                                    sdk.WordBoundary.addEventListener { _, e ->
                                        if (e.boundaryType == SpeechSynthesisBoundaryType.Word) {
                                            collector.word(
                                                WordBoundary(
                                                    e.audioOffset / 10000,
                                                    e.duration / 10000,
                                                    e.textOffset.toInt(),
                                                    e.wordLength.toInt(),
                                                )
                                            )
                                        }
                                    }
                                    sdk.SpeakTextAsync(request.text)
                                        .get(
                                            SpeechLimits.synthesisTimeoutSeconds,
                                            TimeUnit.SECONDS,
                                        )
                                        .use { result ->
                                            check(
                                                result.reason ==
                                                    ResultReason.SynthesizingAudioCompleted
                                            )
                                            check(!active.cancelled.get())
                                            val audioData = result.audioData
                                            try {
                                                check(collector.write(audioData) > 0)
                                            } finally {
                                                audioData.fill(0)
                                            }
                                            output =
                                                collector.finish(
                                                    request.locale,
                                                    request.voice,
                                                )
                                        }
                                } finally {
                                    // Do not hold the cancellation lock while awaiting SDK cleanup.
                                    synchronized(active) { active.sdk = null }
                                    runCatching {
                                        sdk.StopSpeakingAsync().get(2, TimeUnit.SECONDS)
                                    }
                                }
                            }
                        } finally {
                            collector.clear()
                            active.collector = null
                        }
                    }
                } catch (_: java.util.concurrent.TimeoutException) {
                    failed = "synthesis_timeout"
                } catch (_: LinkageError) {
                    // Native SDK load/ABI failure must leave the text response usable.
                    failed = "speech_runtime_unavailable"
                } catch (_: Exception) {
                    failed = "synthesis_failed"
                } finally {
                    if (job === active) job = null
                    busy.set(false)
                }
                val packageData = output
                val code = failed
                if (packageData != null) {
                    Log.i(
                        "KundiTts",
                        "synthesis_ready pcm_bytes=${packageData.pcm.size} visemes=${packageData.visemes.size}",
                    )
                } else {
                    Log.w("KundiTts", "synthesis_failed code=${code ?: "synthesis_failed"}")
                }
                post {
                    if (disposed || active.cancelled.get()) packageData?.pcm?.fill(0)
                    else if (packageData != null) ready(packageData)
                    else error(code ?: "synthesis_failed")
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            busy.set(false)
            job = null
            return false
        }
        return true
    }

    override fun cancel() {
        job?.cancel()
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        cancel()
        executor.shutdown()
    }
}
