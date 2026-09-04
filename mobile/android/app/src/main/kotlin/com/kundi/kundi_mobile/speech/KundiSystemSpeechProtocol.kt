package com.kundi.kundi_mobile.speech

internal object KundiSystemSpeechProtocol {
    const val version = 1
    const val commandChannel = "kundi/system_speech/commands"
    const val eventChannel = "kundi/system_speech/events"

    fun parse(arguments: Any?): KundiSpeechCommand {
        val envelope = arguments as? Map<*, *>
            ?: throw KundiSpeechProtocolException("command envelope must be a map")
        if ((envelope["version"] as? Number)?.toInt() != version) {
            throw KundiSpeechProtocolException("unsupported protocol version")
        }
        if (envelope["kind"] != "command") {
            throw KundiSpeechProtocolException("envelope kind must be command")
        }
        val name = envelope["name"] as? String
            ?: throw KundiSpeechProtocolException("command name is required")
        val payload = (envelope["payload"] as? Map<*, *>).orEmpty()
        return when (name) {
            "availability" -> KundiSpeechCommand.Availability
            "permissionStatus" -> KundiSpeechCommand.PermissionStatus
            "requestPermission" -> KundiSpeechCommand.RequestPermission
            "openAppSettings" -> KundiSpeechCommand.OpenAppSettings
            "stopListening" -> KundiSpeechCommand.StopListening
            "cancelListening" -> KundiSpeechCommand.CancelListening
            "dispose" -> KundiSpeechCommand.Dispose
            "startListening" -> {
                val requestId = (payload["requestId"] as? String)?.trim().orEmpty()
                if (requestId.isEmpty()) {
                    throw KundiSpeechProtocolException("requestId is required")
                }
                val maxResults = (payload["maxResults"] as? Number)?.toInt() ?: 3
                if (maxResults !in 1..3) {
                    throw KundiSpeechProtocolException("maxResults must be between 1 and 3")
                }
                KundiSpeechCommand.StartListening(
                    requestId = requestId,
                    locale = localeFor(payload["locale"] as? String),
                    partialResults = payload["partialResults"] as? Boolean ?: true,
                    maxResults = maxResults,
                    qaTelemetryEnabled = payload["qaTelemetryEnabled"] as? Boolean ?: false,
                )
            }
            else -> throw KundiSpeechProtocolException("unknown command")
        }
    }

    fun localeFor(raw: String?): String =
        when (raw?.trim()?.lowercase()) {
            "kk", "kk-kz" -> "kk-KZ"
            "ru", "ru-kz", "ru-ru" -> "ru-RU"
            else -> "ru-RU"
        }

    fun event(name: String, payload: Map<String, Any?> = emptyMap()): Map<String, Any?> =
        mapOf(
            "version" to version,
            "kind" to "event",
            "name" to name,
            "payload" to payload,
        )
}

internal sealed interface KundiSpeechCommand {
    data object Availability : KundiSpeechCommand
    data object PermissionStatus : KundiSpeechCommand
    data object RequestPermission : KundiSpeechCommand
    data object OpenAppSettings : KundiSpeechCommand
    data class StartListening(
        val requestId: String,
        val locale: String,
        val partialResults: Boolean,
        val maxResults: Int,
        val qaTelemetryEnabled: Boolean,
    ) : KundiSpeechCommand
    data object StopListening : KundiSpeechCommand
    data object CancelListening : KundiSpeechCommand
    data object Dispose : KundiSpeechCommand
}

internal class KundiSpeechProtocolException(message: String) : IllegalArgumentException(message)
