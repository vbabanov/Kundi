package com.kundi.kundi_mobile.tts

data class SpeechRequest(
    val generation: Long,
    val text: String,
    val token: String,
    val expiresAtMs: Long,
    val region: String,
    val locale: String,
    val voice: String,
    val endpoint: String = "https://$region.api.cognitive.microsoft.com",
)

interface Synthesizer {
    fun start(
        request: SpeechRequest,
        event: (String) -> Unit,
        ready: (SpeechPackage) -> Unit,
        error: (String) -> Unit,
    ): Boolean

    fun cancel()

    fun dispose()
}

interface PcmPlayer {
    fun start(pcm: ByteArray): Boolean

    fun pump()

    val positionMs: Long
    val completed: Boolean

    fun pause()

    fun release()
}

/** All methods and callbacks run on the host main loop; adapter marshals callbacks. */
class SpeechEngine(
    private val synth: Synthesizer,
    private val playerFactory: () -> PcmPlayer,
    private val emit: (Long, String, Map<String, Any>) -> Unit,
    private val now: () -> Long,
) {
    private var generation: Long? = null
    private var latestGeneration = 0L
    private var player: PcmPlayer? = null
    private var audio: SpeechPackage? = null
    private var cursor: VisemeCursor? = null
    private var disposed = false
    val active: Boolean
        get() = generation != null

    fun start(request: SpeechRequest): Boolean {
        if (disposed || request.generation <= latestGeneration) return false
        cancel()
        latestGeneration = request.generation
        generation = request.generation
        val id = request.generation
        if (request.expiresAtMs <= now() + SpeechLimits.tokenMarginMs) {
            fail(id, "token_expired")
            return false
        }
        val spoken =
            try {
                SpeechLimits.spokenText(request.text)
            } catch (_: Exception) {
                fail(id, "text_bounds")
                return false
            }
        val accepted =
            synth.start(
                request.copy(text = spoken),
                event = { name -> if (current(id)) emit(id, name, emptyMap()) },
                ready = { packageData ->
                    if (!current(id)) packageData.pcm.fill(0)
                    else
                        try {
                            val timeline = SpeechTimeline.build(spoken, packageData)
                            audio = packageData
                            cursor = VisemeCursor(timeline)
                            emit(
                                id,
                                "synthesisReady",
                                mapOf(
                                    "durationMs" to packageData.durationMs,
                                    "visemeCount" to packageData.visemes.size,
                                    "wordCount" to packageData.words.size,
                                    "nonZeroVisemeCount" to
                                        packageData.visemes.count { it.id != 0 },
                                    "pcmBytes" to packageData.pcm.size,
                                    "sampleRate" to packageData.sampleRate,
                                    "timelineCount" to timeline.size,
                                ),
                            )
                            val nextPlayer = playerFactory()
                            player = nextPlayer
                            if (!nextPlayer.start(packageData.pcm)) fail(id, "audio_focus")
                            else emit(id, "playbackStarted", emptyMap())
                        } catch (_: Exception) {
                            packageData.pcm.fill(0)
                            fail(id, "audio_invalid")
                        }
                },
                error = { code -> fail(id, code) },
            )
        if (!accepted) fail(id, "synthesis_busy")
        return accepted
    }

    fun tick() {
        val id = generation ?: return
        val track = player ?: return
        try {
            track.pump()
            cursor?.due(track.positionMs)?.let { emit(id, "visemeDue", mapOf("viseme" to it.name)) }
            if (track.completed) {
                generation = null
                release()
                emit(id, "playbackCompleted", emptyMap())
            }
        } catch (_: Exception) {
            fail(id, "playback_failed")
        }
    }

    fun cancel() {
        val id = generation
        generation = null // Invalidate before stopping SDK or releasing AudioTrack.
        synth.cancel()
        release()
        if (id != null && !disposed) emit(id, "playbackCancelled", emptyMap())
    }

    private fun release() {
        player?.release()
        player = null
        audio?.pcm?.fill(0)
        audio = null
        cursor = null
    }

    private fun current(id: Long) = !disposed && generation == id

    private fun fail(id: Long, code: String) {
        if (!current(id)) return
        generation = null
        synth.cancel()
        release()
        emit(id, "speechError", mapOf("code" to code))
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        cancel()
        synth.dispose()
    }
}
