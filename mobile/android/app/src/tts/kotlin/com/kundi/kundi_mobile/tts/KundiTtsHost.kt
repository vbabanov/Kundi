package com.kundi.kundi_mobile.tts

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object KundiTtsHost {
    private var plugin: TtsPlugin? = null

    @JvmStatic
    fun register(activity: Activity, engine: FlutterEngine) {
        plugin?.dispose()
        plugin = TtsPlugin(activity, engine)
    }

    @JvmStatic
    fun onPause() {
        plugin?.cancel()
    }

    @JvmStatic
    fun onDestroy() {
        plugin?.dispose()
        plugin = null
    }
}

private class TtsPlugin(private val activity: Activity, flutter: FlutterEngine) :
    EventChannel.StreamHandler {
    private val handler = Handler(Looper.getMainLooper())
    private var disposed = false
    private var sink: EventChannel.EventSink? = null
    private val methods = MethodChannel(flutter.dartExecutor.binaryMessenger, "kundi/tts/commands")
    private val events = EventChannel(flutter.dartExecutor.binaryMessenger, "kundi/tts/events")
    private val synth = AzureSpeechSynthesizer { callback -> handler.post { callback() } }
    private val engine =
        SpeechEngine(
            synth,
            { AndroidPcmPlayer(activity) { cancel() } },
            { id, name, payload ->
                if (!disposed)
                    sink?.success(mapOf("generation" to id, "name" to name, "payload" to payload))
            },
            System::currentTimeMillis,
        )
    private val tick =
        object : Runnable {
            override fun run() {
                if (!disposed) {
                    engine.tick()
                    if (engine.active) handler.postDelayed(this, 20)
                }
            }
        }
    private val screenOff =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == Intent.ACTION_SCREEN_OFF) cancel()
            }
        }

    init {
        if (Build.VERSION.SDK_INT >= 33)
            activity.registerReceiver(
                screenOff,
                IntentFilter(Intent.ACTION_SCREEN_OFF),
                Context.RECEIVER_NOT_EXPORTED,
            )
        else activity.registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
        events.setStreamHandler(this)
        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "speak" -> {
                        if (
                            disposed ||
                                sink == null ||
                                activity.isFinishing ||
                                !activity.hasWindowFocus()
                        ) {
                            result.success(false)
                        } else {
                            val args = call.arguments as Map<*, *>
                            val token = args["authorization_token"] as String
                            val region = args["region"] as String
                            val locale = args["locale"] as String
                            val voice = args["voice"] as String
                            require(token.length in 1..16384 && Regex("[a-z0-9]+").matches(region))
                            require(
                                (locale == "ru-RU" && voice == "ru-RU-SvetlanaNeural") ||
                                    (locale == "kk-KZ" && voice == "kk-KZ-AigulNeural")
                            )
                            require(args["audio_format"] == "raw-24khz-16bit-mono-pcm")
                            val text = args["text"] as String
                            require(text.length <= SpeechLimits.maxContentChars)
                            val hash =
                                java.security.MessageDigest.getInstance("SHA-256")
                                    .digest(text.toByteArray(Charsets.UTF_8))
                                    .joinToString("") { "%02x".format(it) }
                            require(hash == args["message_content_sha256"])
                            result.success(
                                engine.start(
                                    SpeechRequest(
                                        (args["generation"] as Number).toLong(),
                                        text,
                                        token,
                                        (args["expires_at_ms"] as Number).toLong(),
                                        region,
                                        locale,
                                        voice,
                                        args["endpoint"] as String,
                                    )
                                )
                            )
                            handler.removeCallbacks(tick)
                            handler.post(tick)
                        }
                    }
                    "cancel" -> {
                        cancel()
                        result.success(null)
                    }
                    "dispose" -> {
                        dispose()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("speech_command_invalid", "Speech unavailable", null)
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        cancel()
        sink = null
    }

    fun cancel() {
        engine.cancel()
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        engine.dispose()
        sink = null
        handler.removeCallbacks(tick)
        activity.unregisterReceiver(screenOff)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}
