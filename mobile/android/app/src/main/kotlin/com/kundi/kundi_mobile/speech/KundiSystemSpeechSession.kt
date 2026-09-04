package com.kundi.kundi_mobile.speech

internal class KundiSystemSpeechSession {
    enum class Phase { LISTENING, STOPPING }

    data class Active(val requestId: String, val locale: String, val startedAtMillis: Long, val phase: Phase)

    private var active: Active? = null
    var disposed: Boolean = false
        private set

    fun start(requestId: String, locale: String, nowMillis: Long): Boolean {
        if (disposed || active != null) return false
        active = Active(requestId, locale, nowMillis, Phase.LISTENING)
        return true
    }

    fun stop(): Active? {
        val current = active ?: return null
        if (current.phase == Phase.STOPPING) return null
        return current.copy(phase = Phase.STOPPING).also { active = it }
    }

    fun current(requestId: String? = null): Active? {
        val current = active ?: return null
        return if (requestId == null || current.requestId == requestId) current else null
    }

    fun finish(requestId: String): Active? {
        val current = current(requestId) ?: return null
        active = null
        return current
    }

    fun cancel(): Active? = active.also { active = null }

    fun dispose(): Boolean {
        if (disposed) return false
        disposed = true
        active = null
        return true
    }
}
