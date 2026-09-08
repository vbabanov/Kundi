package com.kundi.kundi_mobile.speech

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

internal class KundiSystemSpeechPlugin(
    val activity: Activity,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {
    private val handler = Handler(Looper.getMainLooper())
    private val session = KundiSystemSpeechSession()
    private val methodChannel = MethodChannel(messenger, KundiSystemSpeechProtocol.commandChannel)
    private val eventChannel = EventChannel(messenger, KundiSystemSpeechProtocol.eventChannel)
    private var events: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var timeout: Runnable? = null
    private var nativeSessionGeneration = 0
    private val qaSessions = linkedMapOf<String, QaSession>()

    init {
        eventChannel.setStreamHandler(this)
        methodChannel.setMethodCallHandler { call, result ->
            if (call.method != "command") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            handler.post {
                runCatching {
                    val command = KundiSystemSpeechProtocol.parse(call.arguments)
                    commandResult(command, execute(command))
                }
                    .onSuccess(result::success)
                    .onFailure {
                        result.error("invalid_command", it.message ?: "invalid speech command", null)
                    }
            }
        }
    }

    private fun commandResult(command: KundiSpeechCommand, accepted: Boolean): Map<String, Any?> =
        when (command) {
            KundiSpeechCommand.Availability ->
                mapOf(
                    "accepted" to accepted,
                    "available" to SpeechRecognizer.isRecognitionAvailable(activity),
                    "onDeviceAvailable" to (Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)),
                )
            KundiSpeechCommand.PermissionStatus ->
                mapOf("accepted" to accepted, "permission" to permissionToken())
            else -> mapOf("accepted" to accepted)
        }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun execute(command: KundiSpeechCommand): Boolean {
        if (session.disposed && command != KundiSpeechCommand.Dispose) return false
        return when (command) {
            KundiSpeechCommand.Availability -> emitAvailability()
            KundiSpeechCommand.PermissionStatus -> emitPermissionStatus()
            KundiSpeechCommand.RequestPermission -> requestPermission()
            KundiSpeechCommand.OpenAppSettings -> openAppSettings()
            is KundiSpeechCommand.StartListening -> startListening(command)
            KundiSpeechCommand.StopListening -> stopListening()
            KundiSpeechCommand.CancelListening -> cancelListening("cancelled")
            KundiSpeechCommand.Dispose -> dispose()
        }
    }

    private fun emitAvailability(): Boolean {
        val available = SpeechRecognizer.isRecognitionAvailable(activity)
        val onDevice = Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)
        emit("recognitionAvailable", mapOf("available" to available, "onDeviceAvailable" to onDevice))
        return available
    }

    private fun permissionGranted(): Boolean =
        Build.VERSION.SDK_INT < 23 || activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun permissionPermanentlyDenied(): Boolean {
        val requested = activity.getPreferences(Activity.MODE_PRIVATE).getBoolean(permissionAskedKey, false)
        val rationale = Build.VERSION.SDK_INT >= 23 &&
            activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)
        return KundiSystemSpeechPolicy.permissionState(
            granted = permissionGranted(),
            previouslyAsked = requested,
            shouldShowRationale = rationale,
        ) == KundiSystemSpeechPolicy.PermissionState.PERMANENTLY_DENIED
    }

    private fun emitPermissionStatus(): Boolean {
        when {
            permissionGranted() -> emit("permissionGranted")
            permissionPermanentlyDenied() -> emit("permissionPermanentlyDenied")
            else -> emit("permissionRequired")
        }
        return permissionGranted()
    }

    private fun permissionToken(): String =
        when {
            permissionGranted() -> "granted"
            permissionPermanentlyDenied() -> "permanentlyDenied"
            else -> "required"
        }

    private fun requestPermission(): Boolean {
        if (permissionGranted()) {
            emit("permissionGranted")
            return true
        }
        if (permissionPermanentlyDenied()) {
            emit("permissionPermanentlyDenied")
            return false
        }
        if (Build.VERSION.SDK_INT >= 23) {
            activity.getPreferences(Activity.MODE_PRIVATE).edit().putBoolean(permissionAskedKey, true).apply()
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), permissionRequestCode)
        }
        return true
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != permissionRequestCode || permissions.none { it == Manifest.permission.RECORD_AUDIO }) return false
        handler.post {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                emit("permissionGranted")
            } else if (permissionPermanentlyDenied()) {
                emit("permissionPermanentlyDenied")
            } else {
                emit("permissionDenied")
            }
        }
        return true
    }

    private fun openAppSettings(): Boolean {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null))
        activity.startActivity(intent)
        return true
    }

    private fun startListening(command: KundiSpeechCommand.StartListening): Boolean {
        qaEvent(command.requestId, "startCommandReceived", enabled = command.qaTelemetryEnabled)
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            emitError(command.requestId, "unavailable")
            return false
        }
        if (!permissionGranted()) {
            emit(if (permissionPermanentlyDenied()) "permissionPermanentlyDenied" else "permissionRequired")
            return false
        }
        if (!session.start(command.requestId, command.locale, elapsedMillis())) {
            qaEvent(
                command.requestId,
                "nativeSessionStartRejected",
                enabled = command.qaTelemetryEnabled,
                outcome = "busy",
            )
            emitError(command.requestId, "busy")
            return false
        }
        val qaSession = registerQaSession(command)
        qaEvent(command.requestId, "nativeSessionStarted", session = qaSession)
        val speechRecognizer = recognizer ?: SpeechRecognizer.createSpeechRecognizer(activity).also { recognizer = it }
        speechRecognizer.setRecognitionListener(listener(command.requestId))
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, command.locale)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, command.partialResults)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, command.maxResults)
        }
        return runCatching {
            // Locale-only acceptance evidence: deliberately excludes request
            // identifiers, recognized text, credentials, and student data.
            Log.i("KundiVoiceLocale", "recognition_locale=${command.locale}")
            speechRecognizer.startListening(intent)
            emit("listeningStarted", requestPayload(command.requestId))
            scheduleTimeout(command.requestId)
            true
        }.getOrElse {
            session.finish(command.requestId)
            emitError(command.requestId, "unavailable")
            false
        }
    }

    private fun stopListening(): Boolean {
        val active = session.stop() ?: return false
        qaEvent(active.requestId, "stopCommandReceived")
        return runCatching { recognizer?.stopListening(); true }
            .getOrElse {
                finishError(active.requestId, "audio_error")
                false
            }
    }

    private fun cancelListening(reason: String): Boolean {
        val active = session.cancel() ?: return false
        qaEvent(active.requestId, "nativeTerminalAccepted", outcome = reason)
        clearTimeout()
        runCatching { recognizer?.cancel() }
        emit("recognitionCancelled", requestPayload(active.requestId) + ("reason" to reason))
        return true
    }

    fun cancelForLifecycle() {
        handler.post { cancelListening("lifecycle") }
    }

    fun dispose(): Boolean {
        if (!session.dispose()) return false
        clearTimeout()
        runCatching { recognizer?.cancel() }
        runCatching { recognizer?.destroy() }
        recognizer = null
        emit("disposed")
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        events = null
        return true
    }

    private fun listener(requestId: String): RecognitionListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            qaEvent(requestId, "onReadyForSpeech")
            emitIfActive(requestId, "readyForSpeech")
        }
        override fun onBeginningOfSpeech() {
            qaEvent(requestId, "onBeginningOfSpeech")
            emitIfActive(requestId, "beginningOfSpeech")
        }
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() {
            qaEvent(requestId, "onEndOfSpeech")
            emitIfActive(requestId, "endOfSpeech")
        }
        override fun onPartialResults(results: Bundle?) {
            val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim().orEmpty()
            if (text.isNotEmpty() && session.current(requestId) != null) {
                emit("partialResult", requestPayload(requestId) + ("text" to text))
            }
        }
        override fun onResults(results: Bundle?) {
            val candidates = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION).orEmpty()
            val text = candidates.firstOrNull()?.trim().orEmpty()
            val qaSession = qaSessions[requestId]
            val ordinal = qaSession?.nextFinalOrdinal() ?: 1
            qaEvent(requestId, "onResults", ordinal = ordinal, textLength = text.length)
            val active = session.finish(requestId)
            if (active == null) {
                qaEvent(
                    requestId,
                    "nativeTerminalSuppressed",
                    ordinal = ordinal,
                    outcome = "inactive_request",
                )
                return
            }
            qaSession?.terminalAccepted = true
            qaEvent(requestId, "nativeTerminalAccepted", ordinal = ordinal, outcome = "results")
            clearTimeout()
            if (text.isEmpty()) {
                emit("noSpeech", requestPayload(requestId) + ("code" to "no_match"))
                return
            }
            val confidence = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)?.firstOrNull()?.takeIf { it >= 0f }
            emit(
                "finalResult",
                requestPayload(requestId) + mapOf(
                    "text" to text,
                    "confidence" to confidence,
                    "locale" to active.locale,
                    "durationMs" to (elapsedMillis() - active.startedAtMillis).coerceAtLeast(0L),
                ),
            )
        }
        override fun onError(error: Int) {
            val code = KundiSystemSpeechPolicy.errorCode(error)
            qaEvent(requestId, "onError", outcome = code)
            if (session.current(requestId) == null) {
                qaEvent(requestId, "nativeTerminalSuppressed", outcome = "inactive_request")
                return
            }
            if (code == "no_speech" || code == "no_match") {
                session.finish(requestId)
                qaSessions[requestId]?.terminalAccepted = true
                qaEvent(requestId, "nativeTerminalAccepted", outcome = code)
                clearTimeout()
                emit("noSpeech", requestPayload(requestId) + ("code" to code))
            } else {
                finishError(requestId, code)
            }
        }
        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private fun scheduleTimeout(requestId: String) {
        clearTimeout()
        timeout = Runnable {
            if (session.finish(requestId) == null) return@Runnable
            qaSessions[requestId]?.terminalAccepted = true
            qaEvent(requestId, "nativeTerminalAccepted", outcome = "timeout")
            runCatching { recognizer?.cancel() }
            emitError(requestId, "timeout")
        }.also { handler.postDelayed(it, KundiSystemSpeechPolicy.maximumListeningMillis) }
    }

    private fun finishError(requestId: String, code: String) {
        if (session.finish(requestId) == null) {
            qaEvent(requestId, "nativeTerminalSuppressed", outcome = code)
            return
        }
        qaSessions[requestId]?.terminalAccepted = true
        qaEvent(requestId, "nativeTerminalAccepted", outcome = code)
        clearTimeout()
        emitError(requestId, code)
    }

    private fun emitIfActive(requestId: String, name: String) {
        if (session.current(requestId) != null) emit(name, requestPayload(requestId))
    }

    private fun emitError(requestId: String, code: String) {
        emit("recognitionError", requestPayload(requestId) + ("code" to code))
    }

    private fun requestPayload(requestId: String) = mapOf("requestId" to requestId)
    private fun emit(name: String, payload: Map<String, Any?> = emptyMap()) {
        if (!session.disposed || name == "disposed") {
            events?.success(KundiSystemSpeechProtocol.event(name, payload))
        }
    }

    private fun clearTimeout() {
        timeout?.let(handler::removeCallbacks)
        timeout = null
    }

    private fun elapsedMillis(): Long = android.os.SystemClock.elapsedRealtime()

    private fun registerQaSession(command: KundiSpeechCommand.StartListening): QaSession? {
        if (!command.qaTelemetryEnabled) return null
        val qaSession = QaSession(generation = ++nativeSessionGeneration)
        qaSessions[command.requestId] = qaSession
        while (qaSessions.size > maximumRetainedQaSessions) {
            qaSessions.remove(qaSessions.keys.first())
        }
        return qaSession
    }

    private fun qaEvent(
        requestId: String,
        event: String,
        enabled: Boolean = qaSessions[requestId] != null,
        session: QaSession? = qaSessions[requestId],
        ordinal: Int? = null,
        textLength: Int? = null,
        outcome: String? = null,
    ) {
        if (!enabled) return
        val payload = JSONObject()
            .put("timestampMs", System.currentTimeMillis())
            .put("event", event)
            .put("recognitionRequestId", requestId)
        session?.let { payload.put("nativeSessionGeneration", it.generation) }
        ordinal?.let { payload.put("ordinal", it) }
        textLength?.let { payload.put("textLength", it) }
        outcome?.let { payload.put("outcome", it) }
        Log.i(qaLogTag, payload.toString())
    }

    private data class QaSession(
        val generation: Int,
        var finalOrdinal: Int = 0,
        var terminalAccepted: Boolean = false,
    ) {
        fun nextFinalOrdinal(): Int = ++finalOrdinal
    }

    private companion object {
        const val permissionRequestCode = 9471
        const val permissionAskedKey = "kundi_speech_permission_asked"
        const val qaLogTag = "KUNDI_VOICE_QA"
        const val maximumRetainedQaSessions = 32
    }
}
