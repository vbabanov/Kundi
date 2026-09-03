package com.kundi.kundi_mobile.avatar

internal object KundiNativeAvatarProtocol {
    const val version = 1

    val animationNames =
        listOf(
            "Standing",
            "Idle",
            "Waiting",
            "Talking",
            "Talking2",
            "Talking3",
            "Dansing",
        )

    val emotionBlendShapes =
        mapOf(
            "Neutral" to "Fcl_ALL_Neutral",
            "Joy" to "Fcl_ALL_Joy",
            "Fun" to "Fcl_ALL_Fun",
            "Sorrow" to "Fcl_ALL_Sorrow",
            "Surprised" to "Fcl_ALL_Surprised",
            "Angry" to "Fcl_ALL_Angry",
        )

    val visemeBlendShapes =
        mapOf(
            "A" to "Fcl_MTH_A",
            "I" to "Fcl_MTH_I",
            "U" to "Fcl_MTH_U",
            "E" to "Fcl_MTH_E",
            "O" to "Fcl_MTH_O",
        )

    val expectedFaceBlendShapes =
        listOf(
            "Fcl_ALL_Neutral",
            "Fcl_ALL_Angry",
            "Fcl_ALL_Fun",
            "Fcl_ALL_Joy",
            "Fcl_ALL_Sorrow",
            "Fcl_ALL_Surprised",
            "Fcl_EYE_Close",
            "Fcl_EYE_Close_R",
            "Fcl_EYE_Close_L",
            "Fcl_MTH_A",
            "Fcl_MTH_I",
            "Fcl_MTH_U",
            "Fcl_MTH_E",
            "Fcl_MTH_O",
        )

    fun parseEnvelope(arguments: Any?): NativeAvatarCommand {
        val envelope = arguments as? Map<*, *>
            ?: throw ProtocolException("command envelope must be a map")
        if (envelope["version"] != version) {
            throw ProtocolException("unsupported protocol version")
        }
        if (envelope["kind"] != "command") {
            throw ProtocolException("envelope kind must be command")
        }

        val name = envelope["name"] as? String
            ?: throw ProtocolException("command name is required")
        val payload = (envelope["payload"] as? Map<*, *>).orEmpty()

        return when (name) {
            "setVisible" -> {
                val visible = payload["visible"] as? Boolean
                    ?: throw ProtocolException("visible is required")
                NativeAvatarCommand.SetVisible(visible)
            }
            "playIdle" ->
                NativeAvatarCommand.PlayAnimation(
                    animation = "Idle",
                    cadence = NativeAvatarAnimationCadence.ACTIVE,
                )
            "playWaiting" ->
                NativeAvatarCommand.PlayAnimation(
                    animation = "Waiting",
                    cadence = NativeAvatarAnimationCadence.ACTIVE,
                )
            "playTalking" -> {
                val variant = (payload["variant"] as? Number)?.toInt()
                    ?: throw ProtocolException("talking variant is required")
                val animation =
                    when (variant) {
                        1 -> "Talking"
                        2 -> "Talking2"
                        3 -> "Talking3"
                        else -> throw ProtocolException("talking variant must be 1, 2, or 3")
                    }
                NativeAvatarCommand.PlayAnimation(
                    animation = animation,
                    cadence = NativeAvatarAnimationCadence.ACTIVE,
                )
            }
            "playCelebration" ->
                NativeAvatarCommand.PlayAnimation(
                    animation = "Dansing",
                    cadence = NativeAvatarAnimationCadence.ACTIVE,
                )
            "settleRestPose" -> NativeAvatarCommand.SettleRestPose
            "startPresentationPriming" -> {
                val rendererGeneration =
                    (payload["rendererGeneration"] as? Number)?.toInt()
                        ?: throw ProtocolException("renderer generation is required")
                val textureId =
                    (payload["textureId"] as? Number)?.toLong()
                        ?: throw ProtocolException("texture ID is required")
                if (rendererGeneration < 0) {
                    throw ProtocolException("renderer generation must not be negative")
                }
                if (textureId < 0L) {
                    throw ProtocolException("texture ID must not be negative")
                }
                NativeAvatarCommand.StartPresentationPriming(
                    rendererGeneration = rendererGeneration,
                    textureId = textureId,
                )
            }
            "freeze" -> NativeAvatarCommand.Freeze
            "setEmotion" -> {
                val emotion = payload["emotion"] as? String
                    ?: throw ProtocolException("emotion is required")
                if (emotion !in emotionBlendShapes) {
                    throw ProtocolException("unknown emotion: $emotion")
                }
                NativeAvatarCommand.SetEmotion(emotion)
            }
            "blink" -> NativeAvatarCommand.Blink
            "setViseme" -> {
                val viseme = payload["viseme"] as? String
                    ?: throw ProtocolException("viseme is required")
                if (viseme !in visemeBlendShapes) {
                    throw ProtocolException("unknown viseme: $viseme")
                }
                NativeAvatarCommand.SetViseme(viseme)
            }
            "resetFace" -> NativeAvatarCommand.ResetFace
            else -> throw ProtocolException("unknown command: $name")
        }
    }

    fun event(
        name: String,
        payload: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> =
        mapOf(
            "version" to version,
            "kind" to "event",
            "name" to name,
            "payload" to payload,
        )
}

internal sealed interface NativeAvatarCommand {
    data class SetVisible(val visible: Boolean) : NativeAvatarCommand
    data class PlayAnimation(
        val animation: String,
        val cadence: NativeAvatarAnimationCadence,
    ) : NativeAvatarCommand
    data class SetEmotion(val emotion: String) : NativeAvatarCommand
    data class SetViseme(val viseme: String) : NativeAvatarCommand
    data class StartPresentationPriming(
        val rendererGeneration: Int,
        val textureId: Long,
    ) : NativeAvatarCommand
    data object SettleRestPose : NativeAvatarCommand
    data object Freeze : NativeAvatarCommand
    data object Blink : NativeAvatarCommand
    data object ResetFace : NativeAvatarCommand
}

internal enum class NativeAvatarAnimationCadence {
    ACTIVE,
    PASSIVE_BURST,
}

internal class ProtocolException(message: String) : IllegalArgumentException(message)

internal enum class RendererLifecycleState {
    CREATED,
    RUNNING,
    PAUSED,
    DISPOSED,
}

internal class RendererLifecycle {
    var state: RendererLifecycleState = RendererLifecycleState.CREATED
        private set

    fun resume(): Boolean {
        if (state == RendererLifecycleState.DISPOSED) return false
        val changed = state != RendererLifecycleState.RUNNING
        state = RendererLifecycleState.RUNNING
        return changed
    }

    fun pause(): Boolean {
        if (state == RendererLifecycleState.DISPOSED) return false
        val changed = state != RendererLifecycleState.PAUSED
        state = RendererLifecycleState.PAUSED
        return changed
    }

    fun dispose(): Boolean {
        if (state == RendererLifecycleState.DISPOSED) return false
        state = RendererLifecycleState.DISPOSED
        return true
    }
}
