package com.kundi.kundi_mobile.avatar

import android.view.Surface
import android.view.TextureView
import com.google.android.filament.android.UiHelper
import io.flutter.view.TextureRegistry
import kotlin.math.roundToInt

internal data class KundiAvatarRenderSize(
    val surfaceWidth: Int,
    val surfaceHeight: Int,
    val viewWidth: Int,
    val viewHeight: Int,
)

internal interface KundiAvatarRenderTarget {
    val swapChainFlags: Long
    val retainedTextureEntryCount: Int

    fun attach(listener: Listener)

    fun detach()

    fun onRendererDisposed()

    interface Listener {
        fun onSurfaceAvailable(nativeWindow: Any)

        fun onSurfaceCleanup()

        fun onSurfaceSizeChanged(size: KundiAvatarRenderSize)
    }
}

internal class KundiTextureViewRenderTarget(
    private val textureView: TextureView,
    private val renderScale: Double,
    private val releaseView: (TextureView) -> Unit,
) : KundiAvatarRenderTarget {
    private val uiHelper =
        UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK).apply {
            isOpaque = false
        }
    private var listener: KundiAvatarRenderTarget.Listener? = null
    private var released = false

    override val swapChainFlags: Long
        get() = uiHelper.swapChainFlags

    override val retainedTextureEntryCount: Int = 0

    override fun attach(listener: KundiAvatarRenderTarget.Listener) {
        check(!released) { "TextureView render target is released" }
        check(this.listener == null) { "TextureView render target is already attached" }
        this.listener = listener
        uiHelper.renderCallback =
            object : UiHelper.RendererCallback {
                override fun onNativeWindowChanged(surface: Surface) {
                    listener.onSurfaceAvailable(surface)
                }

                override fun onDetachedFromSurface() {
                    listener.onSurfaceCleanup()
                }

                override fun onResized(width: Int, height: Int) {
                    if (width <= 0 || height <= 0) return
                    val viewWidth = textureView.width.takeIf { it > 0 } ?: width
                    val viewHeight = textureView.height.takeIf { it > 0 } ?: height
                    val renderWidth = (viewWidth * renderScale).roundToInt().coerceAtLeast(1)
                    val renderHeight = (viewHeight * renderScale).roundToInt().coerceAtLeast(1)
                    textureView.surfaceTexture?.setDefaultBufferSize(renderWidth, renderHeight)
                    listener.onSurfaceSizeChanged(
                        KundiAvatarRenderSize(
                            surfaceWidth = renderWidth,
                            surfaceHeight = renderHeight,
                            viewWidth = viewWidth,
                            viewHeight = viewHeight,
                        ),
                    )
                }
            }
        uiHelper.attachTo(textureView)
    }

    override fun detach() {
        if (listener == null) return
        uiHelper.detach()
        uiHelper.renderCallback = null
        listener = null
    }

    override fun onRendererDisposed() {
        if (released) return
        released = true
        detach()
        releaseView(textureView)
    }
}

internal data class KundiFlutterTextureSize(
    val logicalWidth: Double,
    val logicalHeight: Double,
    val devicePixelRatio: Double,
    val renderScale: Double,
    val physicalViewWidth: Int,
    val physicalViewHeight: Int,
    val renderWidth: Int,
    val renderHeight: Int,
) {
    companion object {
        fun fromLogical(
            logicalWidth: Double,
            logicalHeight: Double,
            devicePixelRatio: Double,
            renderScale: Double,
        ): KundiFlutterTextureSize {
            require(logicalWidth > 0.0 && logicalHeight > 0.0) {
                "Texture logical size must be positive"
            }
            require(devicePixelRatio > 0.0) { "Device pixel ratio must be positive" }
            require(renderScale in 0.5..1.0) { "Render scale must be between 0.5 and 1.0" }
            val physicalViewWidth =
                (logicalWidth * devicePixelRatio).roundToInt().coerceAtLeast(1)
            val physicalViewHeight =
                (logicalHeight * devicePixelRatio).roundToInt().coerceAtLeast(1)
            return KundiFlutterTextureSize(
                logicalWidth = logicalWidth,
                logicalHeight = logicalHeight,
                devicePixelRatio = devicePixelRatio,
                renderScale = renderScale,
                physicalViewWidth = physicalViewWidth,
                physicalViewHeight = physicalViewHeight,
                renderWidth = (physicalViewWidth * renderScale).roundToInt().coerceAtLeast(1),
                renderHeight = (physicalViewHeight * renderScale).roundToInt().coerceAtLeast(1),
            )
        }
    }

    fun asRenderSize(): KundiAvatarRenderSize =
        KundiAvatarRenderSize(
            surfaceWidth = renderWidth,
            surfaceHeight = renderHeight,
            viewWidth = physicalViewWidth,
            viewHeight = physicalViewHeight,
        )
}

internal interface KundiSurfaceProducerCallback {
    fun onSurfaceAvailable()

    fun onSurfaceCleanup()
}

internal interface KundiSurfaceProducerHandle {
    val id: Long

    fun setSize(width: Int, height: Int)

    fun getSurface(): Any

    fun getForcedNewSurface(): Any

    fun setCallback(callback: KundiSurfaceProducerCallback?)

    fun release()
}

internal class FlutterSurfaceProducerHandle(
    private val producer: TextureRegistry.SurfaceProducer,
) : KundiSurfaceProducerHandle {
    override val id: Long
        get() = producer.id()

    override fun setSize(width: Int, height: Int) {
        producer.setSize(width, height)
    }

    override fun getSurface(): Any = producer.surface

    override fun getForcedNewSurface(): Any = producer.forcedNewSurface

    override fun setCallback(callback: KundiSurfaceProducerCallback?) {
        producer.setCallback(
            callback?.let { activeCallback ->
                object : TextureRegistry.SurfaceProducer.Callback {
                    override fun onSurfaceAvailable() {
                        activeCallback.onSurfaceAvailable()
                    }

                    override fun onSurfaceCleanup() {
                        activeCallback.onSurfaceCleanup()
                    }
                }
            },
        )
    }

    override fun release() {
        producer.release()
    }
}

internal class KundiFlutterTextureRenderTarget(
    private val producer: KundiSurfaceProducerHandle,
    initialSize: KundiFlutterTextureSize,
) : KundiAvatarRenderTarget {
    private var size = initialSize
    private var listener: KundiAvatarRenderTarget.Listener? = null
    private var released = false

    init {
        producer.setSize(initialSize.renderWidth, initialSize.renderHeight)
    }

    val textureId: Long
        get() = producer.id

    override val swapChainFlags: Long = transparentSwapChainFlag

    override val retainedTextureEntryCount: Int
        get() = if (released) 0 else 1

    override fun attach(listener: KundiAvatarRenderTarget.Listener) {
        check(!released) { "Flutter texture render target is released" }
        check(this.listener == null) { "Flutter texture render target is already attached" }
        this.listener = listener
        producer.setCallback(
            object : KundiSurfaceProducerCallback {
                override fun onSurfaceAvailable() {
                    val activeListener = this@KundiFlutterTextureRenderTarget.listener ?: return
                    activeListener.onSurfaceSizeChanged(size.asRenderSize())
                    activeListener.onSurfaceAvailable(producer.getSurface())
                }

                override fun onSurfaceCleanup() {
                    this@KundiFlutterTextureRenderTarget.listener?.onSurfaceCleanup()
                }
            },
        )
        listener.onSurfaceSizeChanged(size.asRenderSize())
        listener.onSurfaceAvailable(producer.getSurface())
    }

    fun resize(nextSize: KundiFlutterTextureSize): Boolean {
        check(!released) { "Flutter texture render target is released" }
        if (size == nextSize) return false
        listener?.onSurfaceCleanup()
        size = nextSize
        producer.setSize(nextSize.renderWidth, nextSize.renderHeight)
        listener?.let { activeListener ->
            activeListener.onSurfaceSizeChanged(nextSize.asRenderSize())
            activeListener.onSurfaceAvailable(producer.getForcedNewSurface())
        }
        return true
    }

    override fun detach() {
        val activeListener = listener ?: return
        producer.setCallback(null)
        listener = null
        activeListener.onSurfaceCleanup()
    }

    override fun onRendererDisposed() {
        detach()
    }

    fun release() {
        if (released) return
        detach()
        released = true
        producer.release()
    }

    private companion object {
        // Filament's transparent swap-chain flag; UiHelper returns the same value when opaque=false.
        const val transparentSwapChainFlag = 1L
    }
}
