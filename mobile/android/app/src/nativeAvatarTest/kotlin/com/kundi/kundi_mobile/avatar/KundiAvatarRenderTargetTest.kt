package com.kundi.kundi_mobile.avatar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class KundiAvatarRenderTargetTest {
    @Test
    fun `logical size converts to physical pixels before render scale`() {
        val size =
            KundiFlutterTextureSize.fromLogical(
                logicalWidth = 160.0,
                logicalHeight = 220.0,
                devicePixelRatio = 2.75,
                renderScale = 0.75,
            )

        assertEquals(440, size.physicalViewWidth)
        assertEquals(605, size.physicalViewHeight)
        assertEquals(330, size.renderWidth)
        assertEquals(454, size.renderHeight)
    }

    @Test
    fun `texture ID and last frame survive renderer disposal`() {
        val producer = FakeSurfaceProducer(id = 73L)
        val target = KundiFlutterTextureRenderTarget(producer, defaultSize())
        val firstListener = FakeRenderTargetListener()

        target.attach(firstListener)
        target.onRendererDisposed()

        assertEquals(73L, target.textureId)
        assertEquals(1, target.retainedTextureEntryCount)
        assertEquals(0, producer.releaseCalls)
        assertEquals(1, firstListener.cleanupCalls)

        val recreatedListener = FakeRenderTargetListener()
        target.attach(recreatedListener)
        assertEquals(1, recreatedListener.availableSurfaces.size)
        assertEquals(0, producer.forcedSurfaceCalls)
        assertEquals(0, producer.releaseCalls)
    }

    @Test
    fun `resize recreates surface without replacing texture entry`() {
        val producer = FakeSurfaceProducer(id = 9L)
        val target = KundiFlutterTextureRenderTarget(producer, defaultSize())
        val listener = FakeRenderTargetListener()
        target.attach(listener)

        val changed =
            target.resize(
                KundiFlutterTextureSize.fromLogical(200.0, 240.0, 2.0, 0.75),
            )

        assertTrue(changed)
        assertEquals(9L, target.textureId)
        assertEquals(1, listener.cleanupCalls)
        assertEquals(2, listener.availableSurfaces.size)
        assertEquals(1, producer.forcedSurfaceCalls)
        assertEquals(300, producer.width)
        assertEquals(360, producer.height)
        assertEquals(0, producer.releaseCalls)
        assertFalse(target.resize(KundiFlutterTextureSize.fromLogical(200.0, 240.0, 2.0, 0.75)))
    }

    @Test
    fun `producer callbacks clean and recreate the swap chain surface`() {
        val producer = FakeSurfaceProducer(id = 4L)
        val target = KundiFlutterTextureRenderTarget(producer, defaultSize())
        val listener = FakeRenderTargetListener()
        target.attach(listener)

        producer.registeredCallback?.onSurfaceCleanup()
        producer.registeredCallback?.onSurfaceAvailable()

        assertEquals(1, listener.cleanupCalls)
        assertEquals(2, listener.availableSurfaces.size)
        assertEquals(2, listener.sizes.size)
    }

    @Test
    fun `terminal producer release is idempotent`() {
        val producer = FakeSurfaceProducer(id = 11L)
        val target = KundiFlutterTextureRenderTarget(producer, defaultSize())
        target.attach(FakeRenderTargetListener())

        target.release()
        target.release()

        assertEquals(1, producer.releaseCalls)
        assertEquals(0, target.retainedTextureEntryCount)
        assertEquals(null, producer.registeredCallback)
        assertThrows(IllegalStateException::class.java) {
            target.attach(FakeRenderTargetListener())
        }
    }

    private fun defaultSize(): KundiFlutterTextureSize =
        KundiFlutterTextureSize.fromLogical(160.0, 220.0, 2.0, 0.75)
}

private class FakeSurfaceProducer(
    override val id: Long,
) : KundiSurfaceProducerHandle {
    var width = 0
    var height = 0
    var registeredCallback: KundiSurfaceProducerCallback? = null
    var forcedSurfaceCalls = 0
    var releaseCalls = 0
    private var surfaceGeneration = 0

    override fun setSize(width: Int, height: Int) {
        this.width = width
        this.height = height
    }

    override fun getSurface(): Any = "surface-${surfaceGeneration++}"

    override fun getForcedNewSurface(): Any {
        forcedSurfaceCalls++
        return "forced-surface-${surfaceGeneration++}"
    }

    override fun setCallback(callback: KundiSurfaceProducerCallback?) {
        registeredCallback = callback
    }

    override fun release() {
        releaseCalls++
    }
}

private class FakeRenderTargetListener : KundiAvatarRenderTarget.Listener {
    val availableSurfaces = mutableListOf<Any>()
    val sizes = mutableListOf<KundiAvatarRenderSize>()
    var cleanupCalls = 0

    override fun onSurfaceAvailable(nativeWindow: Any) {
        availableSurfaces += nativeWindow
    }

    override fun onSurfaceCleanup() {
        cleanupCalls++
    }

    override fun onSurfaceSizeChanged(size: KundiAvatarRenderSize) {
        sizes += size
    }
}
