package com.kundi.kundi_mobile.avatar

import android.content.ComponentCallbacks2
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.kundi.kundi_mobile.BuildConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

internal class KundiNativeAvatarTextureManager(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textureRegistry: TextureRegistry,
    private val rendererEligible: Boolean,
) {
    private val hosts = LinkedHashMap<Long, KundiNativeAvatarTextureHost>()
    private val methodChannel = MethodChannel(messenger, methodChannelName)
    private val eventChannel = EventChannel(messenger, eventChannelName)
    private val pendingEvents = ArrayDeque<Map<String, Any?>>()
    private var eventSink: EventChannel.EventSink? = null
    private var disposed = false

    init {
        methodChannel.setMethodCallHandler(::handleMethodCall)
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                    while (pendingEvents.isNotEmpty()) {
                        sink.success(pendingEvents.removeFirst())
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
    }

    fun onHostResume() {
        if (!disposed) hosts.values.toList().forEach(KundiNativeAvatarTextureHost::onHostResume)
    }

    fun onHostPause() {
        if (!disposed) hosts.values.toList().forEach(KundiNativeAvatarTextureHost::onHostPause)
    }

    fun onAppUiHidden() {
        if (!disposed) hosts.values.toList().forEach(KundiNativeAvatarTextureHost::onAppUiHidden)
    }

    fun onTrimMemory(level: Int) {
        if (disposed) return
        hosts.values.toList().forEach { host ->
            host.onMemoryPressure(
                level = level,
                blockRecreationUntilHidden =
                    level < ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN,
            )
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        hosts.values.toList().forEach(KundiNativeAvatarTextureHost::dispose)
        hosts.clear()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        pendingEvents.clear()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("disposed", "Native avatar texture manager is disposed", null)
            return
        }
        runCatching {
            when (call.method) {
                "create" -> createHost(requireArguments(call.arguments))
                "resize" -> resizeHost(requireArguments(call.arguments))
                "command" -> commandHost(requireArguments(call.arguments))
                "dispose" -> disposeHost(requireArguments(call.arguments))
                else -> null
            }
        }.onSuccess { payload ->
            if (payload == null) {
                result.notImplemented()
            } else {
                result.success(payload)
            }
        }.onFailure { error ->
            val code =
                when (error) {
                    is ProtocolException, is IllegalArgumentException -> "invalid_request"
                    else -> "texture_failed"
                }
            emitManagerError(code, error)
            result.error(code, error.message, null)
        }
    }

    private fun createHost(arguments: Map<*, *>): Map<String, Any?> {
        check(rendererEligible) { "Native avatar is unsupported on this device" }
        require(arguments["protocolVersion"] == KundiNativeAvatarProtocol.version) {
            "Unsupported native avatar protocol version"
        }
        val renderScale = number(arguments, "renderScale").coerceIn(0.5, 1.0)
        val passiveBurstIntervalMillis =
            number(arguments, "passiveBurstIntervalMillis").toLong().also {
                require(it in 10_000L..20_000L) { "Invalid passive burst interval" }
            }
        val passiveBurstDurationMillis =
            number(arguments, "passiveBurstDurationMillis").toLong().also {
                require(it in 300L..1_500L) { "Invalid passive burst duration" }
            }
        val placement = KundiHomeAvatarPlacement.fromArguments(arguments)
        val size = parseSize(arguments, renderScale)
        val producer =
            textureRegistry.createSurfaceProducer(TextureRegistry.SurfaceLifecycle.manual)
        val renderTarget =
            KundiFlutterTextureRenderTarget(
                producer = FlutterSurfaceProducerHandle(producer),
                initialSize = size,
            )
        val textureId = renderTarget.textureId
        check(textureId !in hosts) { "Texture ID is already active: $textureId" }
        val host =
            runCatching {
                KundiNativeAvatarTextureHost(
                    context = context,
                    textureId = textureId,
                    renderTarget = renderTarget,
                    renderScale = renderScale,
                    placement = placement,
                    passiveBurstIntervalMillis = passiveBurstIntervalMillis,
                    passiveBurstDurationMillis = passiveBurstDurationMillis,
                    emitEvent = { emit(textureId, it) },
                    onDisposed = { hosts.remove(textureId) },
                )
            }.getOrElse { error ->
                renderTarget.release()
                throw error
            }
        hosts[textureId] = host
        emit(
            textureId,
            KundiNativeAvatarProtocol.event(
                "textureCreated",
                mapOf(
                    "textureId" to textureId,
                    "renderWidth" to size.renderWidth,
                    "renderHeight" to size.renderHeight,
                    "surfaceLifecycle" to "manual",
                ),
            ),
        )
        return mapOf(
            "textureId" to textureId,
            "renderWidth" to size.renderWidth,
            "renderHeight" to size.renderHeight,
            "physicalViewWidth" to size.physicalViewWidth,
            "physicalViewHeight" to size.physicalViewHeight,
        )
    }

    private fun resizeHost(arguments: Map<*, *>): Map<String, Any?> {
        val host = requireHost(arguments)
        val size = parseSize(arguments, host.renderScale)
        val changed = host.resize(size)
        return mapOf(
            "textureId" to host.textureId,
            "changed" to changed,
            "renderWidth" to size.renderWidth,
            "renderHeight" to size.renderHeight,
        )
    }

    private fun commandHost(arguments: Map<*, *>): Map<String, Any?> {
        val host = requireHost(arguments)
        val envelope = arguments["envelope"]
            ?: throw IllegalArgumentException("envelope is required")
        host.execute(KundiNativeAvatarProtocol.parseEnvelope(envelope))
        return mapOf("accepted" to true, "textureId" to host.textureId)
    }

    private fun disposeHost(arguments: Map<*, *>): Map<String, Any?> {
        val textureId = textureId(arguments)
        val host = hosts.remove(textureId)
        host?.dispose()
        return mapOf("disposed" to (host != null), "textureId" to textureId)
    }

    private fun requireHost(arguments: Map<*, *>): KundiNativeAvatarTextureHost {
        val textureId = textureId(arguments)
        return checkNotNull(hosts[textureId]) { "Unknown texture ID: $textureId" }
    }

    private fun parseSize(
        arguments: Map<*, *>,
        renderScale: Double,
    ): KundiFlutterTextureSize =
        KundiFlutterTextureSize.fromLogical(
            logicalWidth = number(arguments, "logicalWidth"),
            logicalHeight = number(arguments, "logicalHeight"),
            devicePixelRatio = number(arguments, "devicePixelRatio"),
            renderScale = renderScale,
        )

    private fun emit(
        textureId: Long,
        event: Map<String, Any?>,
    ) {
        val taggedEvent = event + mapOf("textureId" to textureId)
        Log.d(logTag, "texture=$textureId event=$event")
        val sink = eventSink
        if (sink != null) {
            sink.success(taggedEvent)
            return
        }
        if (pendingEvents.size == maxPendingEvents) {
            pendingEvents.removeFirst()
        }
        pendingEvents.addLast(taggedEvent)
    }

    private fun emitManagerError(
        code: String,
        error: Throwable,
    ) {
        Log.e(logTag, "Texture manager failure: $code", error)
    }

    private fun requireArguments(value: Any?): Map<*, *> =
        value as? Map<*, *> ?: throw IllegalArgumentException("arguments must be a map")

    private fun textureId(arguments: Map<*, *>): Long =
        (arguments["textureId"] as? Number)?.toLong()
            ?: throw IllegalArgumentException("textureId is required")

    private fun number(
        arguments: Map<*, *>,
        name: String,
    ): Double =
        (arguments[name] as? Number)?.toDouble()
            ?: throw IllegalArgumentException("$name is required")

    private companion object {
        const val methodChannelName = "kundi/native_avatar/texture/commands"
        const val eventChannelName = "kundi/native_avatar/texture/events"
        const val maxPendingEvents = 64
        const val logTag = "KundiNativeAvatar"
    }
}

internal class KundiNativeAvatarTextureHost(
    private val context: Context,
    val textureId: Long,
    private val renderTarget: KundiFlutterTextureRenderTarget,
    val renderScale: Double,
    private val placement: KundiHomeAvatarPlacement,
    passiveBurstIntervalMillis: Long,
    passiveBurstDurationMillis: Long,
    private val emitEvent: (Map<String, Any?>) -> Unit,
    private val onDisposed: () -> Unit,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var disposed = false
    private val session =
        KundiNativeAvatarRendererSession(
            gracePeriodMillis = BuildConfig.KUNDI_HOME_AVATAR_GRACE_PERIOD_MS,
            scheduler =
                object : KundiAvatarSessionScheduler {
                    override fun schedule(
                        delayMillis: Long,
                        task: Runnable,
                    ) {
                        mainHandler.postDelayed(task, delayMillis)
                    }

                    override fun cancel(task: Runnable) {
                        mainHandler.removeCallbacks(task)
                    }
                },
            rendererFactory =
                KundiAvatarRendererFactory {
                    KundiFilamentRenderer(
                        context = context,
                        renderTarget = renderTarget,
                        renderScale = renderScale,
                        placement = placement,
                        passiveBurstIntervalMillis = passiveBurstIntervalMillis,
                        passiveBurstDurationMillis = passiveBurstDurationMillis,
                        emitEvent = emitEvent,
                    )
                },
            clearModelCache = KundiNativeAvatarModelCache::clear,
            emitEvent = emitEvent,
        )

    init {
        session.setAttached(true)
    }

    fun execute(command: NativeAvatarCommand) {
        check(!disposed) { "Native avatar texture host is disposed" }
        if (command is NativeAvatarCommand.StartPresentationPriming) {
            check(command.textureId == textureId) {
                "Presentation priming Texture ID does not match the active host"
            }
        }
        session.execute(command)
    }

    fun resize(size: KundiFlutterTextureSize): Boolean {
        check(!disposed) { "Native avatar texture host is disposed" }
        return renderTarget.resize(size)
    }

    fun onHostResume() {
        if (!disposed) session.onHostResume()
    }

    fun onHostPause() {
        if (!disposed) session.onHostPause()
    }

    fun onAppUiHidden() {
        if (!disposed) session.onAppUiHidden()
    }

    fun onMemoryPressure(
        level: Int,
        blockRecreationUntilHidden: Boolean,
    ) {
        if (!disposed) {
            session.onMemoryPressure(level, blockRecreationUntilHidden)
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        session.setAttached(false)
        session.terminate()
        renderTarget.release()
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "textureReleased",
                mapOf(
                    "textureId" to textureId,
                    "retainedTextureEntries" to renderTarget.retainedTextureEntryCount,
                ),
            ),
        )
        onDisposed()
    }
}
