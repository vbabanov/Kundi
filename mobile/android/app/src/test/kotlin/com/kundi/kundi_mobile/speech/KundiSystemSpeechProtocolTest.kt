package com.kundi.kundi_mobile.speech

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KundiSystemSpeechProtocolTest {
    @Test
    fun parsesVersionedStartAndNormalizesLocales() {
        val command = KundiSystemSpeechProtocol.parse(
            mapOf(
                "version" to 1,
                "kind" to "command",
                "name" to "startListening",
                "payload" to mapOf("requestId" to "request-1", "locale" to "ru-KZ", "partialResults" to true, "maxResults" to 3),
            ),
        ) as KundiSpeechCommand.StartListening
        assertEquals("request-1", command.requestId)
        assertEquals("ru-RU", command.locale)
        assertFalse(command.qaTelemetryEnabled)
        assertEquals("kk-KZ", KundiSystemSpeechProtocol.localeFor("kk"))
        assertEquals("ru-RU", KundiSystemSpeechProtocol.localeFor("unknown"))
    }

    @Test
    fun qaTelemetryMustBeExplicitlyEnabledPerStartCommand() {
        val command = KundiSystemSpeechProtocol.parse(
            mapOf(
                "version" to 1,
                "kind" to "command",
                "name" to "startListening",
                "payload" to mapOf(
                    "requestId" to "request-qa",
                    "locale" to "ru-RU",
                    "qaTelemetryEnabled" to true,
                ),
            ),
        ) as KundiSpeechCommand.StartListening

        assertTrue(command.qaTelemetryEnabled)
    }

    @Test(expected = KundiSpeechProtocolException::class)
    fun rejectsUnsupportedProtocolVersion() {
        KundiSystemSpeechProtocol.parse(mapOf("version" to 2, "kind" to "command", "name" to "availability"))
    }

    @Test
    fun sessionAllowsOneRequestAndSuppressesLateOrDuplicateFinals() {
        val session = KundiSystemSpeechSession()
        assertTrue(session.start("one", "ru-RU", 100L))
        assertFalse(session.start("two", "kk-KZ", 101L))
        assertEquals(KundiSystemSpeechSession.Phase.STOPPING, session.stop()?.phase)
        assertEquals("one", session.finish("one")?.requestId)
        assertNull(session.finish("one"))
    }

    @Test
    fun cancelAndDisposeSuppressLateResultsAndCleanupOnce() {
        val session = KundiSystemSpeechSession()
        assertTrue(session.start("one", "ru-RU", 100L))
        assertEquals("one", session.cancel()?.requestId)
        assertNull(session.finish("one"))
        assertTrue(session.dispose())
        assertFalse(session.dispose())
        assertFalse(session.start("two", "ru-RU", 200L))
    }

    @Test
    fun mapsStableErrorsPermissionAndTimeout() {
        assertEquals("network_error", KundiSystemSpeechPolicy.errorCode(1))
        assertEquals("no_match", KundiSystemSpeechPolicy.errorCode(7))
        assertEquals("permission_denied", KundiSystemSpeechPolicy.errorCode(9))
        assertEquals("unknown", KundiSystemSpeechPolicy.errorCode(999))
        assertEquals(
            KundiSystemSpeechPolicy.PermissionState.REQUIRED,
            KundiSystemSpeechPolicy.permissionState(false, false, false),
        )
        assertEquals(
            KundiSystemSpeechPolicy.PermissionState.PERMANENTLY_DENIED,
            KundiSystemSpeechPolicy.permissionState(false, true, false),
        )
        assertFalse(KundiSystemSpeechPolicy.timedOut(100L, 20_099L))
        assertTrue(KundiSystemSpeechPolicy.timedOut(100L, 20_100L))
    }

    @Test
    fun defaultRecognizerPolicyDoesNotForceOnDeviceEngines() {
        assertFalse(KundiSystemSpeechPolicy.useOnDeviceRecognizer(29, false))
        assertFalse(KundiSystemSpeechPolicy.useOnDeviceRecognizer(31, true))
    }
}
