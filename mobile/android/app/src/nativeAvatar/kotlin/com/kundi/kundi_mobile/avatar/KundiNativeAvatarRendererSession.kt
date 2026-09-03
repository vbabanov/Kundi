package com.kundi.kundi_mobile.avatar

internal interface KundiAvatarRendererBackend {
    fun setAttached(value: Boolean)

    fun onHostResume()

    fun onHostPause()

    fun execute(command: NativeAvatarCommand)

    fun dispose()
}

internal fun interface KundiAvatarRendererFactory {
    fun create(): KundiAvatarRendererBackend
}

internal interface KundiAvatarSessionScheduler {
    fun schedule(
        delayMillis: Long,
        task: Runnable,
    )

    fun cancel(task: Runnable)
}

internal class KundiNativeAvatarRendererSession(
    private val gracePeriodMillis: Long,
    private val scheduler: KundiAvatarSessionScheduler,
    private val rendererFactory: KundiAvatarRendererFactory,
    private val clearModelCache: () -> Unit,
    private val emitEvent: (Map<String, Any?>) -> Unit,
) {
    private var renderer: KundiAvatarRendererBackend? = null
    private var attached = false
    private var hostResumed = true
    private var visible = false
    private var destroyScheduled = false
    private var recreateBlockedUntilHidden = false
    private var terminated = false
    private var rendererCreateCount = 0
    private var modelLoadCount = 0
    private var fullDisposeCount = 0
    private var retainedAnimationCommand: NativeAvatarCommand? = null
    private var retainedEmotionCommand: NativeAvatarCommand.SetEmotion? = null
    private var retainedVisemeCommand: NativeAvatarCommand.SetViseme? = null

    private val delayedDestroy =
        Runnable {
            destroyScheduled = false
            if (!terminated && (!visible || !attached || !hostResumed)) {
                destroyRenderer(reason = "grace_period")
            }
        }

    init {
        require(gracePeriodMillis >= 0L) {
            "Avatar renderer grace period must not be negative"
        }
    }

    fun setAttached(value: Boolean) {
        if (terminated || attached == value) return
        attached = value
        renderer?.setAttached(value)
        if (value && visible && hostResumed && !recreateBlockedUntilHidden) {
            cancelDestroy()
            ensureRenderer().setAttached(true)
        } else if (!value) {
            scheduleDestroy()
        }
        emitSessionEvent(if (value) "attached" else "detached")
    }

    fun setVisible(value: Boolean) {
        if (terminated) return
        visible = value
        if (!value) {
            recreateBlockedUntilHidden = false
            renderer?.execute(NativeAvatarCommand.SetVisible(false))
            scheduleDestroy()
            emitSessionEvent("offscreen")
            return
        }

        cancelDestroy()
        if (recreateBlockedUntilHidden) {
            emitSessionEvent("memoryPressureFallback")
            return
        }
        val activeRenderer = ensureRenderer()
        activeRenderer.setAttached(attached)
        if (hostResumed) {
            activeRenderer.onHostResume()
        } else {
            activeRenderer.onHostPause()
        }
        activeRenderer.execute(NativeAvatarCommand.SetVisible(true))
        emitSessionEvent("visible")
    }

    fun execute(command: NativeAvatarCommand) {
        if (command is NativeAvatarCommand.SetVisible) {
            setVisible(command.visible)
            return
        }
        check(!terminated) { "Avatar renderer session is terminated" }
        check(visible && !recreateBlockedUntilHidden) {
            "Avatar renderer is not visible"
        }
        retain(command)
        checkNotNull(renderer) { "Avatar renderer is not available" }
            .execute(command)
    }

    fun onHostResume() {
        if (terminated) return
        hostResumed = true
        if (visible && attached && !recreateBlockedUntilHidden) {
            cancelDestroy()
            ensureRenderer().onHostResume()
        }
        emitSessionEvent("hostResumed")
    }

    fun onHostPause() {
        if (terminated) return
        hostResumed = false
        renderer?.onHostPause()
        scheduleDestroy()
        emitSessionEvent("hostPaused")
    }

    fun onMemoryPressure(
        level: Int,
        blockRecreationUntilHidden: Boolean = true,
    ) {
        if (terminated) return
        recreateBlockedUntilHidden = visible && blockRecreationUntilHidden
        destroyRenderer(reason = "memory_pressure", memoryLevel = level)
        emitSessionEvent("memoryPressure")
    }

    fun onAppUiHidden() {
        if (terminated) return
        recreateBlockedUntilHidden = false
        destroyRenderer(reason = "app_ui_hidden")
        emitSessionEvent("appUiHidden")
    }

    fun terminate() {
        if (terminated) return
        terminated = true
        destroyRenderer(reason = "session_terminated")
        emitSessionEvent("terminated")
    }

    private fun ensureRenderer(): KundiAvatarRendererBackend {
        renderer?.let { return it }
        check(!terminated) { "Avatar renderer session is terminated" }
        return rendererFactory.create().also { created ->
            renderer = created
            rendererCreateCount++
            modelLoadCount++
            created.setAttached(attached)
            if (hostResumed) {
                created.onHostResume()
            } else {
                created.onHostPause()
            }
            replayRetainedState(created)
            emitSessionEvent("rendererCreated")
        }
    }

    private fun retain(command: NativeAvatarCommand) {
        when (command) {
            is NativeAvatarCommand.PlayAnimation,
            NativeAvatarCommand.SettleRestPose,
            NativeAvatarCommand.Freeze,
            -> retainedAnimationCommand = command
            is NativeAvatarCommand.SetEmotion -> retainedEmotionCommand = command
            is NativeAvatarCommand.SetViseme -> retainedVisemeCommand = command
            NativeAvatarCommand.ResetFace -> {
                retainedEmotionCommand = null
                retainedVisemeCommand = null
            }
            is NativeAvatarCommand.StartPresentationPriming -> Unit
            NativeAvatarCommand.Blink,
            is NativeAvatarCommand.SetVisible,
            -> Unit
        }
    }

    private fun replayRetainedState(renderer: KundiAvatarRendererBackend) {
        retainedEmotionCommand?.let(renderer::execute)
        retainedVisemeCommand?.let(renderer::execute)
        retainedAnimationCommand?.let(renderer::execute)
    }

    private fun scheduleDestroy() {
        if (renderer == null || destroyScheduled || terminated) return
        destroyScheduled = true
        scheduler.schedule(gracePeriodMillis, delayedDestroy)
        emitSessionEvent("graceScheduled")
    }

    private fun cancelDestroy() {
        if (!destroyScheduled) return
        scheduler.cancel(delayedDestroy)
        destroyScheduled = false
        emitSessionEvent("graceCancelled")
    }

    private fun destroyRenderer(
        reason: String,
        memoryLevel: Int? = null,
    ) {
        cancelDestroy()
        val activeRenderer = renderer ?: run {
            clearModelCache()
            return
        }
        activeRenderer.setAttached(false)
        activeRenderer.dispose()
        renderer = null
        fullDisposeCount++
        clearModelCache()
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "rendererDisposed",
                diagnostics(
                    status = "fullDisposed",
                    extra =
                        buildMap {
                            put("reason", reason)
                            memoryLevel?.let { put("memoryLevel", it) }
                        },
                ),
            ),
        )
    }

    private fun emitSessionEvent(status: String) {
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "sessionLifecycle",
                diagnostics(status),
            ),
        )
    }

    private fun diagnostics(
        status: String,
        extra: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> =
        buildMap {
            put("status", status)
            put("visible", visible)
            put("attached", attached)
            put("hostResumed", hostResumed)
            put("destroyScheduled", destroyScheduled)
            put("rendererCreateCount", rendererCreateCount)
            put("modelLoadCount", modelLoadCount)
            put("fullDisposeCount", fullDisposeCount)
            put("gracePeriodMillis", gracePeriodMillis)
            putAll(extra)
        }
}
