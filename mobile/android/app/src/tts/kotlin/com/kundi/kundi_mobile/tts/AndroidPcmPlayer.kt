package com.kundi.kundi_mobile.tts

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper

/** Android owns wired/Bluetooth/default media routing. No speakerphone override. */
class AndroidPcmPlayer(context: Context, private val focusLost: () -> Unit) : PcmPlayer {
    private val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val handler = Handler(Looper.getMainLooper())
    private val attributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
    private val listener = AudioManager.OnAudioFocusChangeListener { change ->
        // Queued callbacks from an already released track cannot cancel a new turn.
        if (hasFocus && change != AudioManager.AUDIOFOCUS_GAIN) focusLost()
    }
    private var focus: AudioFocusRequest? = null
    private var hasFocus = false
    private var track: AudioTrack? = null
    private var pcm: ByteArray? = null
    private var written = 0
    private var totalFrames = 0
    private var lastHead = 0L
    private var stagnantTicks = 0

    @Suppress("DEPRECATION")
    override fun start(pcm: ByteArray): Boolean {
        val granted =
            if (Build.VERSION.SDK_INT >= 26) {
                focus =
                    AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                        .setAudioAttributes(attributes)
                        .setAcceptsDelayedFocusGain(false)
                        .setWillPauseWhenDucked(true)
                        .setOnAudioFocusChangeListener(listener, handler)
                        .build()
                manager.requestAudioFocus(focus!!)
            } else
                manager.requestAudioFocus(
                    listener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
                )
        hasFocus = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (!hasFocus) return false
        val minBytes =
            AudioTrack.getMinBufferSize(
                SpeechLimits.sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
        require(minBytes > 0)
        track =
            AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(SpeechLimits.sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .build()
                )
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(maxOf(minBytes, 16384))
                .build()
        require(track!!.state == AudioTrack.STATE_INITIALIZED)
        this.pcm = pcm
        totalFrames = pcm.size / 2
        written = 0
        pump()
        track!!.play()
        return true
    }

    override fun pump() {
        val data = pcm ?: return
        val output = track ?: return
        if (written < data.size) {
            val count =
                output.write(
                    data,
                    written,
                    minOf(16384, data.size - written),
                    AudioTrack.WRITE_NON_BLOCKING,
                )
            check(count >= 0)
            written += count
        }
        val head = output.playbackHeadPosition.toLong() and 0xffffffffL
        if (head == lastHead) stagnantTicks++ else stagnantTicks = 0
        check(stagnantTicks < 250) // Five seconds without forward audio progress.
        lastHead = head
    }

    override val positionMs
        get() = lastHead * 1000 / SpeechLimits.sampleRate

    override val completed
        get() = totalFrames > 0 && lastHead >= totalFrames

    override fun pause() {
        track?.pause()
    }

    @Suppress("DEPRECATION")
    override fun release() {
        val output = track
        track = null
        pcm = null
        if (output != null) {
            runCatching {
                output.pause()
                output.flush()
                output.stop()
            }
            output.release()
        }
        if (hasFocus) {
            hasFocus = false
            if (Build.VERSION.SDK_INT >= 26) focus?.let { manager.abandonAudioFocusRequest(it) }
            else manager.abandonAudioFocus(listener)
        }
        focus = null
    }
}
