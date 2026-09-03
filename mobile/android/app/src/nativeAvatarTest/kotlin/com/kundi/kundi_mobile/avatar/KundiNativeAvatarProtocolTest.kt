package com.kundi.kundi_mobile.avatar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test

class KundiNativeAvatarProtocolTest {
    @Test
    fun `animation contract exactly matches the GLB`() {
        assertEquals(
            listOf(
                "Standing",
                "Idle",
                "Waiting",
                "Talking",
                "Talking2",
                "Talking3",
                "Dansing",
            ),
            KundiNativeAvatarProtocol.animationNames,
        )
    }

    @Test
    fun `talking variants map to their exact animation names`() {
        assertEquals(
            NativeAvatarCommand.PlayAnimation(
                "Talking",
                NativeAvatarAnimationCadence.ACTIVE,
            ),
            parse("playTalking", mapOf("variant" to 1)),
        )
        assertEquals(
            NativeAvatarCommand.PlayAnimation(
                "Talking2",
                NativeAvatarAnimationCadence.ACTIVE,
            ),
            parse("playTalking", mapOf("variant" to 2)),
        )
        assertEquals(
            NativeAvatarCommand.PlayAnimation(
                "Talking3",
                NativeAvatarAnimationCadence.ACTIVE,
            ),
            parse("playTalking", mapOf("variant" to 3)),
        )
    }

    @Test
    fun `visibility and celebration map to runtime commands`() {
        assertEquals(NativeAvatarCommand.SetVisible(false), parse("setVisible", mapOf("visible" to false)))
        assertEquals(
            NativeAvatarCommand.PlayAnimation(
                "Dansing",
                NativeAvatarAnimationCadence.ACTIVE,
            ),
            parse("playCelebration"),
        )
        assertEquals(
            NativeAvatarCommand.PlayAnimation(
                "Idle",
                NativeAvatarAnimationCadence.ACTIVE,
            ),
            parse("playIdle"),
        )
        assertEquals(NativeAvatarCommand.SettleRestPose, parse("settleRestPose"))
        assertEquals(NativeAvatarCommand.Freeze, parse("freeze"))
    }

    @Test
    fun `presentation priming carries renderer generation and Texture ID`() {
        assertEquals(
            NativeAvatarCommand.StartPresentationPriming(
                rendererGeneration = 7,
                textureId = 42L,
            ),
            parse(
                "startPresentationPriming",
                mapOf(
                    "rendererGeneration" to 7,
                    "textureId" to 42L,
                ),
            ),
        )
    }

    @Test
    fun `all 14 retained morph target names are unique`() {
        assertEquals(14, KundiNativeAvatarProtocol.expectedFaceBlendShapes.size)
        assertEquals(
            14,
            KundiNativeAvatarProtocol.expectedFaceBlendShapes.toSet().size,
        )
        assertTrue(
            KundiNativeAvatarProtocol.expectedFaceBlendShapes.containsAll(
                KundiNativeAvatarProtocol.emotionBlendShapes.values,
            ),
        )
        assertTrue(
            KundiNativeAvatarProtocol.expectedFaceBlendShapes.containsAll(
                KundiNativeAvatarProtocol.visemeBlendShapes.values,
            ),
        )
    }

    @Test
    fun `invalid command and protocol version are rejected`() {
        assertThrows(ProtocolException::class.java) {
            parse("playTalking", mapOf("variant" to 4))
        }
        assertThrows(ProtocolException::class.java) {
            KundiNativeAvatarProtocol.parseEnvelope(
                mapOf(
                    "version" to 2,
                    "kind" to "command",
                    "name" to "playIdle",
                    "payload" to emptyMap<String, Any>(),
                ),
            )
        }
        assertThrows(ProtocolException::class.java) {
            parse("notACommand")
        }
    }

    @Test
    fun `lifecycle transitions and repeated dispose are safe`() {
        val lifecycle = RendererLifecycle()
        assertEquals(RendererLifecycleState.CREATED, lifecycle.state)
        assertTrue(lifecycle.resume())
        assertFalse(lifecycle.resume())
        assertTrue(lifecycle.pause())
        assertTrue(lifecycle.dispose())
        assertFalse(lifecycle.dispose())
        assertFalse(lifecycle.resume())
        assertEquals(RendererLifecycleState.DISPOSED, lifecycle.state)
    }

    private fun parse(
        name: String,
        payload: Map<String, Any> = emptyMap(),
    ): NativeAvatarCommand =
        KundiNativeAvatarProtocol.parseEnvelope(
            mapOf(
                "version" to KundiNativeAvatarProtocol.version,
                "kind" to "command",
                "name" to name,
                "payload" to payload,
            ),
        )
}
