package com.kundi.kundi_mobile.avatar

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import com.google.android.filament.Camera
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.SwapChain
import com.google.android.filament.View as FilamentView
import com.google.android.filament.Viewport
import com.google.android.filament.gltfio.Animator
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.max

internal class KundiFilamentRenderer(
    private val context: Context,
    private val renderTarget: KundiAvatarRenderTarget,
    private val renderScale: Double,
    private val placement: KundiHomeAvatarPlacement,
    passiveBurstIntervalMillis: Long,
    passiveBurstDurationMillis: Long,
    private val emitEvent: (Map<String, Any?>) -> Unit,
) : Choreographer.FrameCallback, KundiAvatarRendererBackend {
    private val rendererId = rendererIds.incrementAndGet()
    private val lifecycle = RendererLifecycle()
    private val choreographer = Choreographer.getInstance()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val entityManager = EntityManager.get()
    private val engine = Engine.create()
    private val renderer: Renderer = engine.createRenderer()
    private val scene: Scene = engine.createScene()
    private val filamentView: FilamentView = engine.createView()
    private val cameraEntity = entityManager.create()
    private val camera: Camera = engine.createCamera(cameraEntity)
    private val keyLightEntity = entityManager.create()
    private val fillLightEntity = entityManager.create()
    private val rimLightEntity = entityManager.create()
    private val indirectLight: IndirectLight
    private val materialProvider = UbershaderProvider(engine)
    private val assetLoader = AssetLoader(engine, materialProvider, entityManager)
    private val resourceLoader = ResourceLoader(engine, true)
    private val readyRenderables = IntArray(128)
    private val addedRenderableEntities = HashSet<Int>()
    private val morphBindings = LinkedHashMap<Int, Map<String, Int>>()
    private val faceWeights = HashMap<String, Float>()
    private val animationByName = LinkedHashMap<String, AnimationMetadata>()
    private val blinkReset = Runnable {
        blinkWeight = 0f
        applyFaceWeights()
    }
    private val scheduleRestorationFrame = Runnable(::scheduleFrame)
    private val presentationPriming = KundiPresentationPrimingTracker()
    private val presentationPrimeTimeout = Runnable(::handlePresentationPrimeTimeout)
    private val frameLoop = KundiAvatarFrameLoopGuard()
    private val cadence =
        KundiAvatarCadenceController(
            config =
                KundiAvatarCadenceConfig(
                    passiveBurstIntervalMillis = passiveBurstIntervalMillis,
                    passiveBurstDurationMillis = passiveBurstDurationMillis,
                ),
            scheduler =
                object : KundiAvatarCadenceScheduler {
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
            onPassiveBurstRequested = ::startPassiveIdleAnimation,
            onModeChanged = ::onCadenceModeChanged,
        )

    private var swapChain: SwapChain? = null
    private var asset: FilamentAsset? = null
    private var animator: Animator? = null
    private var sourceBuffer: ByteBuffer? = null
    private var currentAnimation: AnimationPlayback? = null
    private var previousAnimation: PreviousAnimation? = null
    private var fixedAnimationSample: FixedAnimationSample? = null
    private var crossFadeStartedNanos = 0L
    private var blinkWeight = 0f
    private var attached = false
    private var hostResumed = true
    private var requestedVisible = true
    private var frameScheduled = false
    private var modelReady = false
    private var disposed = false
    private var firstFrameEmitted = false
    private var surfaceGeneration = 0
    private var pendingPresentationPriming: NativeAvatarCommand.StartPresentationPriming? = null
    private var activePresentationPriming: NativeAvatarCommand.StartPresentationPriming? = null
    private var restorationFramePending = false
    private var freezeAfterRestorationFrame = false
    private val commandsPendingModelLoad = mutableListOf<NativeAvatarCommand>()
    private var modelSha256 = ""
    private var modelWasPrewarmed = false
    private var configuredRenderWidth = 0
    private var configuredRenderHeight = 0
    private var loadStartedNanos = 0L
    private var metricsWindowStartedNanos = 0L
    private var lastFrameNanos = 0L
    private var frameCount = 0
    private var frameTimeSumNanos = 0L
    private var frameCallbackPostedCount = 0L
    private var frameCallbackCount = 0L
    private var renderedFrameCount = 0L

    init {
        filamentView.scene = scene
        filamentView.camera = camera
        filamentView.blendMode = FilamentView.BlendMode.TRANSLUCENT
        filamentView.isPostProcessingEnabled = true
        filamentView.setShadowingEnabled(false)
        filamentView.sampleCount = 1
        filamentView.antiAliasing = FilamentView.AntiAliasing.NONE
        filamentView.ambientOcclusion = FilamentView.AmbientOcclusion.NONE
        filamentView.dithering = FilamentView.Dithering.NONE
        filamentView.setScreenSpaceRefractionEnabled(false)
        filamentView.multiSampleAntiAliasingOptions =
            FilamentView.MultiSampleAntiAliasingOptions().apply {
                enabled = false
                sampleCount = 1
            }
        filamentView.bloomOptions =
            FilamentView.BloomOptions().apply {
                enabled = false
            }
        filamentView.dynamicResolutionOptions =
            FilamentView.DynamicResolutionOptions().apply {
                enabled = false
            }

        camera.setExposure(12.0f, 1.0f / 125.0f, 100.0f)

        renderer.clearOptions =
            Renderer.ClearOptions().apply {
                clear = true
                discard = true
                clearColor = doubleArrayOf(0.0, 0.0, 0.0, 0.0)
            }

        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 0.98f, 0.95f)
            .intensity(105_000f)
            .direction(-0.22f, -0.32f, -0.92f)
            .castShadows(false)
            .build(engine, keyLightEntity)
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.82f, 0.89f, 1.0f)
            .intensity(42_000f)
            .direction(0.62f, -0.12f, -0.78f)
            .castShadows(false)
            .build(engine, fillLightEntity)
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.88f, 0.91f, 1.0f)
            .intensity(22_000f)
            .direction(-0.28f, -0.08f, 0.96f)
            .castShadows(false)
            .build(engine, rimLightEntity)
        scene.addEntities(intArrayOf(keyLightEntity, fillLightEntity, rimLightEntity))

        indirectLight =
            IndirectLight.Builder()
                .irradiance(1, floatArrayOf(0.96f, 0.97f, 1.0f))
                .intensity(28_000f)
                .build(engine)
        scene.indirectLight = indirectLight

        renderTarget.attach(
            object : KundiAvatarRenderTarget.Listener {
                override fun onSurfaceAvailable(nativeWindow: Any) {
                    destroySwapChain(waitForCompletion = false)
                    surfaceGeneration++
                    swapChain =
                        engine.createSwapChain(
                            nativeWindow,
                            renderTarget.swapChainFlags,
                        )
                    emitEvent(
                        KundiNativeAvatarProtocol.event(
                            "surfaceAvailable",
                            mapOf("surfaceGeneration" to surfaceGeneration),
                        ),
                    )
                    startPendingPresentationPrimingIfPossible()
                    resumeIfPossible()
                }

                override fun onSurfaceCleanup() {
                    resetPresentationPriming(reason = "surface_cleanup")
                    destroySwapChain(waitForCompletion = true)
                    emitEvent(
                        KundiNativeAvatarProtocol.event(
                            "surfaceCleanup",
                            mapOf("surfaceGeneration" to surfaceGeneration),
                        ),
                    )
                }

                override fun onSurfaceSizeChanged(size: KundiAvatarRenderSize) {
                    configureSurface(size)
                }
            },
        )

        emitEvent(KundiNativeAvatarProtocol.event("rendererReady"))
        cadence.startActiveAnimation()
        loadModel()
    }

    override fun setAttached(value: Boolean) {
        if (disposed || attached == value) return
        attached = value
        cadence.setAttached(value)
        if (value) {
            resumeIfPossible()
        } else {
            stopFrames()
        }
    }

    override fun onHostResume() {
        if (disposed) return
        hostResumed = true
        cadence.setHostResumed(true)
        resumeIfPossible()
    }

    override fun onHostPause() {
        if (disposed) return
        hostResumed = false
        cadence.setHostResumed(false)
        if (lifecycle.pause()) {
            emitLifecycle("paused")
        }
        renderer.resetUserTime()
        stopFrames()
    }

    override fun execute(command: NativeAvatarCommand) {
        check(!disposed) { "Renderer is disposed" }
        if (command is NativeAvatarCommand.SetVisible) {
            setVisible(command.visible)
            return
        }
        if (frameLoop.hasFatalError) return
        if (!modelReady) {
            commandsPendingModelLoad += command
            return
        }

        when (command) {
            is NativeAvatarCommand.PlayAnimation -> {
                startAnimation(
                    name = command.animation,
                    loop = true,
                    nowNanos = animationClockNanos(),
                )
                when (command.cadence) {
                    NativeAvatarAnimationCadence.ACTIVE -> cadence.startActiveAnimation()
                    NativeAvatarAnimationCadence.PASSIVE_BURST -> cadence.startPassiveBurst()
                }
            }
            is NativeAvatarCommand.SetEmotion -> setEmotion(command.emotion)
            is NativeAvatarCommand.SetViseme -> setViseme(command.viseme)
            is NativeAvatarCommand.SetVisible -> Unit
            NativeAvatarCommand.SettleRestPose -> settleRestPose()
            is NativeAvatarCommand.StartPresentationPriming ->
                requestPresentationPriming(command)
            NativeAvatarCommand.Freeze -> cadence.freeze()
            NativeAvatarCommand.Blink -> blink()
            NativeAvatarCommand.ResetFace -> resetFace()
        }
    }

    private fun setVisible(value: Boolean) {
        if (disposed || requestedVisible == value) return
        requestedVisible = value
        cadence.setVisible(value)
        if (value) {
            resumeIfPossible()
        } else {
            stopFrames()
        }
    }

    override fun doFrame(frameTimeNanos: Long) {
        frameScheduled = false
        frameCallbackCount++
        if (!shouldRender()) return

        runCatching {
            updateResourceLoading()
            when (
                frameLoop.evaluate(
                    frameTimeNanos = frameTimeNanos,
                    targetFps = cadence.targetFps,
                    oneShotPending = restorationFramePending,
                )
            ) {
                KundiAvatarFrameDirective.STOP -> return@runCatching
                KundiAvatarFrameDirective.THROTTLE -> {
                    scheduleFrame()
                    return@runCatching
                }
                KundiAvatarFrameDirective.RENDER_CADENCED,
                KundiAvatarFrameDirective.RENDER_ONE_SHOT,
                -> Unit
            }
            updateAnimation(frameTimeNanos)
            applyFaceWeights()
            val rendered =
                swapChain?.let { chain ->
                    if (renderer.beginFrame(chain, frameTimeNanos)) {
                        renderer.render(filamentView)
                        renderer.endFrame()
                        true
                    } else {
                        false
                    }
                } ?: false
            if (rendered) {
                renderedFrameCount++
                restorationFramePending = false
                recordPresentationPrimeSubmission()
            }
            recordFrameMetrics(frameTimeNanos, rendered)
            if (rendered && modelReady && !firstFrameEmitted) {
                firstFrameEmitted = true
                emitEvent(
                    KundiNativeAvatarProtocol.event(
                        "firstFrame",
                        mapOf(
                            "elapsedMillis" to
                                (SystemClock.elapsedRealtimeNanos() - loadStartedNanos) /
                                    1_000_000.0,
                            "renderScale" to renderScale,
                        ),
                    ),
                )
            }
            if (rendered && freezeAfterRestorationFrame) {
                freezeAfterRestorationFrame = false
                emitEvent(
                    KundiNativeAvatarProtocol.event(
                        "restPoseFrameRendered",
                        mapOf("normalizedTime" to placement.heroRestNormalizedTime),
                    ),
                )
                cadence.freeze()
            }
        }.onFailure { error ->
            reportFatalRendererError(
                error = error,
                code = "frame_loop_failed",
                fallbackMessage = "Renderer frame loop failed",
            )
            return
        }
        if (restorationFramePending) {
            mainHandler.removeCallbacks(scheduleRestorationFrame)
            mainHandler.post(scheduleRestorationFrame)
        } else {
            scheduleFrame()
        }
    }

    override fun dispose() {
        if (!lifecycle.dispose()) return
        disposed = true
        cadence.dispose()
        resetPresentationPriming(reason = "renderer_disposed", emitReset = false)
        stopFrames()
        mainHandler.removeCallbacks(blinkReset)
        mainHandler.removeCallbacks(scheduleRestorationFrame)
        mainHandler.removeCallbacks(presentationPrimeTimeout)
        var nativeReleaseCompleted = false
        try {
            renderTarget.detach()
            destroySwapChain(waitForCompletion = false)
            if (!modelReady) {
                resourceLoader.asyncCancelLoad()
            }
            resourceLoader.evictResourceData()
            asset?.let { loadedAsset ->
                scene.removeEntities(loadedAsset.entities)
                assetLoader.destroyAsset(loadedAsset)
            }
            asset = null
            animator = null
            sourceBuffer = null
            currentAnimation = null
            previousAnimation = null
            fixedAnimationSample = null
            animationByName.clear()
            morphBindings.clear()
            faceWeights.clear()
            addedRenderableEntities.clear()
            assetLoader.destroy()
            materialProvider.destroyMaterials()
            materialProvider.destroy()
            resourceLoader.destroy()

            scene.indirectLight = null
            engine.destroyIndirectLight(indirectLight)
            val lightEntities = intArrayOf(keyLightEntity, fillLightEntity, rimLightEntity)
            scene.removeEntities(lightEntities)
            lightEntities.forEach { entity ->
                engine.destroyEntity(entity)
                entityManager.destroy(entity)
            }

            engine.destroyRenderer(renderer)
            engine.destroyView(filamentView)
            engine.destroyScene(scene)
            engine.destroyCameraComponent(cameraEntity)
            entityManager.destroy(cameraEntity)
            engine.flushAndWait()
            engine.destroy()
            nativeReleaseCompleted = true
        } finally {
            renderTarget.onRendererDisposed()
            emitEvent(
                KundiNativeAvatarProtocol.event(
                    "rendererResourcesReleased",
                    mapOf(
                        "nativeHandleGroups" to if (nativeReleaseCompleted) 0 else 1,
                        "assets" to if (asset == null) 0 else 1,
                        "renderTargets" to 0,
                        "retainedTextureEntries" to
                            renderTarget.retainedTextureEntryCount,
                        "frameCallbacks" to if (frameScheduled) 1 else 0,
                        "cadenceTimers" to cadence.pendingTimerCount,
                        "releaseCompleted" to nativeReleaseCompleted,
                    ),
                ),
            )
        }
    }

    private fun destroySwapChain(waitForCompletion: Boolean) {
        val activeSwapChain = swapChain ?: return
        engine.destroySwapChain(activeSwapChain)
        if (waitForCompletion) {
            engine.flushAndWait()
        }
        swapChain = null
    }

    private fun configureSurface(size: KundiAvatarRenderSize) {
        val renderWidth = size.surfaceWidth.coerceAtLeast(1)
        val renderHeight = size.surfaceHeight.coerceAtLeast(1)
        filamentView.viewport = Viewport(0, 0, renderWidth, renderHeight)
        if (configuredRenderWidth != renderWidth || configuredRenderHeight != renderHeight) {
            configuredRenderWidth = renderWidth
            configuredRenderHeight = renderHeight
            emitEvent(
                KundiNativeAvatarProtocol.event(
                    "surfaceConfigured",
                    mapOf(
                        "surfaceWidth" to size.surfaceWidth,
                        "surfaceHeight" to size.surfaceHeight,
                        "viewWidth" to size.viewWidth,
                        "viewHeight" to size.viewHeight,
                        "renderWidth" to renderWidth,
                        "renderHeight" to renderHeight,
                        "renderScale" to renderScale,
                    ),
                ),
            )
        }
        val aspect = renderWidth.toDouble() / renderHeight.toDouble()
        camera.setLensProjection(placement.cameraFovDegrees, aspect, nearPlane, farPlane)
        camera.lookAt(
            0.0,
            placement.cameraEyeY,
            placement.cameraDistance,
            0.0,
            placement.cameraTargetY,
            0.0,
            0.0,
            1.0,
            0.0,
        )
    }

    private fun loadModel() {
        loadStartedNanos = SystemClock.elapsedRealtimeNanos()
        emitEvent(KundiNativeAvatarProtocol.event("modelLoading"))

        runCatching {
            val cachedModel = KundiNativeAvatarModelCache.takeOrLoad(context)
            val bytes = cachedModel.bytes
            modelWasPrewarmed = cachedModel.prewarmed
            modelSha256 =
                MessageDigest.getInstance("SHA-256")
                    .digest(bytes)
                    .joinToString(separator = "") { byte -> "%02X".format(byte) }

            val buffer =
                ByteBuffer.allocateDirect(bytes.size)
                    .order(ByteOrder.nativeOrder())
                    .apply {
                        put(bytes)
                        flip()
                    }
            sourceBuffer = buffer
            val loadedAsset =
                checkNotNull(assetLoader.createAsset(buffer)) {
                    "Filament rejected the GLB"
                }
            asset = loadedAsset
            transformToPortraitFrame(loadedAsset)
            check(resourceLoader.asyncBeginLoad(loadedAsset)) {
                "Filament failed to start resource loading"
            }
            animator = loadedAsset.instance.animator
            validateModelMetadata(loadedAsset)
        }.onFailure { error ->
            sourceBuffer = null
            reportFatalRendererError(
                error = error,
                code = "model_load_failed",
                fallbackMessage = "Model load failed",
            )
        }
    }

    private fun validateModelMetadata(loadedAsset: FilamentAsset) {
        val instance = loadedAsset.instance
        val loadedAnimator = instance.animator
        animationByName.clear()
        repeat(loadedAnimator.animationCount) { index ->
            val name = loadedAnimator.getAnimationName(index)
            animationByName[name] =
                AnimationMetadata(
                    index = index,
                    durationSeconds = loadedAnimator.getAnimationDuration(index),
                )
        }

        val renderableManager = engine.renderableManager
        morphBindings.clear()
        loadedAsset.renderableEntities.forEach { entity ->
            val renderableInstance = renderableManager.getInstance(entity)
            if (renderableInstance == 0) return@forEach
            val count = renderableManager.getMorphTargetCount(renderableInstance)
            if (count == 0) return@forEach
            val names = loadedAsset.getMorphTargetNames(entity)
            morphBindings[entity] =
                buildMap {
                    names.take(count).forEachIndexed { index, name ->
                        if (name.isNotBlank()) put(name, index)
                    }
                }
        }

        val namedBlendShapes =
            morphBindings.values
                .flatMap(Map<String, Int>::keys)
                .distinct()
        val jointCount =
            (0 until instance.skinCount).sumOf(instance::getJointCountAt)

        val requiredAnimations = KundiNativeAvatarProtocol.animationNames.toSet()
        check(animationByName.keys.containsAll(requiredAnimations)) {
            "Required animations are missing: ${requiredAnimations - animationByName.keys}"
        }
        check(animationByName.keys == requiredAnimations) {
            "Production avatar animation mismatch: ${animationByName.keys}"
        }
        check(instance.skinCount == expectedSkinCount) {
            "Expected $expectedSkinCount skin, got ${instance.skinCount}"
        }
        check(jointCount == expectedJointCount) {
            "Expected $expectedJointCount joints, got $jointCount"
        }
        check(loadedAsset.renderableEntities.size == expectedMeshCount) {
            "Expected $expectedMeshCount renderables, got ${loadedAsset.renderableEntities.size}"
        }
        check(instance.materialInstances.size == expectedMaterialCount) {
            "Expected $expectedMaterialCount materials, got ${instance.materialInstances.size}"
        }
        val requiredBlendShapes = KundiNativeAvatarProtocol.expectedFaceBlendShapes.toSet()
        val availableBlendShapes = namedBlendShapes.toSet()
        check(availableBlendShapes.containsAll(requiredBlendShapes)) {
            "Required face blend shapes are missing: ${requiredBlendShapes - availableBlendShapes}"
        }
        check(availableBlendShapes == requiredBlendShapes) {
            "Expected ${requiredBlendShapes.size} named face blend shapes, got ${namedBlendShapes.size}"
        }
    }

    private fun transformToPortraitFrame(loadedAsset: FilamentAsset) {
        val center = loadedAsset.boundingBox.center
        val halfExtent = loadedAsset.boundingBox.halfExtent
        val largestExtent =
            max(
                halfExtent[0],
                max(halfExtent[1], halfExtent[2]),
            )
        check(largestExtent > 0f) { "GLB bounding box is empty" }
        val scale = placement.modelHalfExtent / largestExtent
        val transform =
            floatArrayOf(
                scale, 0f, 0f, 0f,
                0f, scale, 0f, 0f,
                0f, 0f, scale, 0f,
                -center[0] * scale + placement.modelOffsetX,
                -center[1] * scale + placement.modelOffsetY,
                -center[2] * scale,
                1f,
            )
        val transformManager = engine.transformManager
        transformManager.setTransform(
            transformManager.getInstance(loadedAsset.root),
            transform,
        )
    }

    private fun updateResourceLoading() {
        if (modelReady) return
        val loadedAsset = asset ?: return
        resourceLoader.asyncUpdateLoad()

        while (true) {
            val count = loadedAsset.popRenderables(readyRenderables)
            if (count == 0) break
            val batch = readyRenderables.copyOf(count)
            scene.addEntities(batch)
            addedRenderableEntities.addAll(batch.toList())
        }
        if (resourceLoader.asyncGetLoadProgress() < 1f) return
        loadedAsset.releaseSourceData()
        sourceBuffer = null
        resourceLoader.evictResourceData()
        modelReady = true
        applyStandingPose()
        val primingWasRequestedBeforeModelReady =
            pendingPresentationPriming != null ||
                activePresentationPriming != null ||
                commandsPendingModelLoad.any {
                    it is NativeAvatarCommand.StartPresentationPriming
                }
        cadence.onModelReady(
            presentationPrimingRequested = primingWasRequestedBeforeModelReady,
        )
        val loadMillis =
            (SystemClock.elapsedRealtimeNanos() - loadStartedNanos) / 1_000_000.0
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "modelLoaded",
                mapOf(
                    "loadMillis" to loadMillis,
                    "skinCount" to loadedAsset.instance.skinCount,
                    "jointCount" to expectedJointCount,
                    "meshCount" to loadedAsset.renderableEntities.size,
                    "materialCount" to loadedAsset.instance.materialInstances.size,
                    "blendShapeCount" to KundiNativeAvatarProtocol.expectedFaceBlendShapes.size,
                    "animationCount" to animationByName.size,
                    "animations" to animationByName.keys.toList(),
                    "blendShapes" to KundiNativeAvatarProtocol.expectedFaceBlendShapes,
                    "modelSha256" to modelSha256,
                    "profile" to "balanced",
                    "renderScale" to renderScale,
                    "prewarmed" to modelWasPrewarmed,
                    "runtimeVerified" to true,
                ),
            ),
        )
        replayCommandsPendingModelLoad()
        startPendingPresentationPrimingIfPossible()
    }

    private fun replayCommandsPendingModelLoad() {
        if (commandsPendingModelLoad.isEmpty()) return
        val commands = commandsPendingModelLoad.toList()
        commandsPendingModelLoad.clear()
        commands.forEach(::execute)
        if (commands.lastOrNull {
                it is NativeAvatarCommand.PlayAnimation ||
                    it === NativeAvatarCommand.SettleRestPose ||
                    it === NativeAvatarCommand.Freeze
            } === NativeAvatarCommand.Freeze
        ) {
            restorationFramePending = true
        }
    }

    private fun startPassiveIdleAnimation() {
        if (!modelReady || disposed) return
        startAnimation("Idle", loop = true, nowNanos = animationClockNanos())
    }

    private fun animationClockNanos(): Long = System.nanoTime()

    private fun startAnimation(
        name: String,
        loop: Boolean,
        nowNanos: Long,
    ) {
        fixedAnimationSample = null
        val metadata =
            animationByName[name]
                ?: throw IllegalArgumentException("Animation is unavailable: $name")
        currentAnimation?.let { current ->
            previousAnimation =
                PreviousAnimation(
                    index = current.metadata.index,
                    timeSeconds = current.elapsedSeconds(nowNanos),
                )
            crossFadeStartedNanos = nowNanos
        }
        currentAnimation =
            AnimationPlayback(
                name = name,
                metadata = metadata,
                loop = loop,
                startedNanos = nowNanos,
            )
        frameLoop.resetCadenceDeadline()
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "animationStarted",
                mapOf("animation" to name, "loop" to loop),
            ),
        )
    }

    private fun updateAnimation(frameTimeNanos: Long) {
        val loadedAnimator = animator ?: return
        fixedAnimationSample?.let { sample ->
            loadedAnimator.applyAnimation(sample.index, sample.timeSeconds)
            loadedAnimator.updateBoneMatrices()
            return
        }
        var playback = currentAnimation ?: return
        var elapsed = playback.elapsedSeconds(frameTimeNanos)
        if (!playback.loop && elapsed >= playback.metadata.durationSeconds) {
            startAnimation("Standing", loop = true, nowNanos = frameTimeNanos)
            playback = checkNotNull(currentAnimation)
            elapsed = 0f
        }
        val sampleTime =
            if (playback.loop && playback.metadata.durationSeconds > 0f) {
                elapsed % playback.metadata.durationSeconds
            } else {
                elapsed.coerceAtMost(playback.metadata.durationSeconds)
            }

        loadedAnimator.applyAnimation(playback.metadata.index, sampleTime)
        previousAnimation?.let { previous ->
            val alpha =
                ((frameTimeNanos - crossFadeStartedNanos).toDouble() / crossFadeDurationNanos)
                    .toFloat()
                    .coerceIn(0f, 1f)
            loadedAnimator.applyCrossFade(previous.index, previous.timeSeconds, alpha)
            if (alpha >= 1f) previousAnimation = null
        }
        loadedAnimator.updateBoneMatrices()
    }

    private fun settleRestPose() {
        applyStandingPose()
        restorationFramePending = true
        freezeAfterRestorationFrame = true
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "restPoseApplied",
                mapOf(
                    "animation" to "Standing",
                    "normalizedTime" to placement.heroRestNormalizedTime,
                    "eyesOpen" to true,
                    "mouthNeutral" to true,
                ),
            ),
        )
        mainHandler.removeCallbacks(scheduleRestorationFrame)
        mainHandler.post(scheduleRestorationFrame)
    }

    private fun applyStandingPose() {
        val loadedAnimator = checkNotNull(animator) { "Animator is unavailable" }
        val metadata =
            animationByName["Standing"]
                ?: throw IllegalArgumentException("Animation is unavailable: Standing")
        val sampleTime = metadata.durationSeconds * placement.heroRestNormalizedTime
        fixedAnimationSample = FixedAnimationSample(metadata.index, sampleTime)
        currentAnimation = null
        previousAnimation = null
        loadedAnimator.applyAnimation(metadata.index, sampleTime)
        loadedAnimator.updateBoneMatrices()
        resetFace()
        setEmotion("Neutral")
    }

    private fun requestPresentationPriming(
        command: NativeAvatarCommand.StartPresentationPriming,
    ) {
        pendingPresentationPriming = command
        startPendingPresentationPrimingIfPossible()
    }

    private fun startPendingPresentationPrimingIfPossible() {
        val command = pendingPresentationPriming ?: return
        if (frameLoop.hasFatalError) {
            pendingPresentationPriming = null
            return
        }
        if (!modelReady || swapChain == null || surfaceGeneration <= 0) return
        applyStandingPose()
        cadence.startActiveAnimation()
        val started =
            presentationPriming.begin(
                KundiPresentationPrimingRequest(
                    rendererGeneration = command.rendererGeneration,
                    textureId = command.textureId,
                    surfaceGeneration = surfaceGeneration,
                    requestedAtMillis = SystemClock.elapsedRealtime(),
                ),
            )
        pendingPresentationPriming = null
        if (!started) return
        activePresentationPriming = command
        mainHandler.removeCallbacks(presentationPrimeTimeout)
        mainHandler.postDelayed(
            presentationPrimeTimeout,
            KundiPresentationPrimingDefaults.presentationPrimeTimeoutMillis,
        )
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "presentationPrimingStarted",
                presentationPayload(
                    command = command,
                    submittedFrameCount = 0,
                    elapsedMillis = 0L,
                ),
            ),
        )
        frameLoop.resetCadenceDeadline()
        scheduleFrame()
    }

    private fun recordPresentationPrimeSubmission() {
        if (frameLoop.hasFatalError) return
        val result =
            presentationPriming.onFrameSubmitted(SystemClock.elapsedRealtime()) ?: return
        val command = activePresentationPriming ?: return
        activePresentationPriming = null
        mainHandler.removeCallbacks(presentationPrimeTimeout)
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "presentationPrimed",
                presentationPayload(
                    command = command,
                    submittedFrameCount = result.submittedFrameCount,
                    elapsedMillis = result.elapsedMillis,
                ),
            ),
        )
    }

    private fun handlePresentationPrimeTimeout() {
        if (frameLoop.hasFatalError) return
        val result =
            presentationPriming.onTimeout(SystemClock.elapsedRealtime()) ?: return
        val command = activePresentationPriming ?: return
        activePresentationPriming = null
        cadence.freeze()
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "presentationPrimeTimedOut",
                presentationPayload(
                    command = command,
                    submittedFrameCount = result.submittedFrameCount,
                    elapsedMillis = result.elapsedMillis,
                ) + mapOf(
                    "code" to "presentation_prime_timeout",
                    "timeoutMillis" to
                        KundiPresentationPrimingDefaults.presentationPrimeTimeoutMillis,
                ),
            ),
        )
    }

    private fun resetPresentationPriming(
        reason: String,
        emitReset: Boolean = true,
    ) {
        val command = activePresentationPriming ?: pendingPresentationPriming
        val reset = presentationPriming.reset()
        activePresentationPriming = null
        pendingPresentationPriming = null
        mainHandler.removeCallbacks(presentationPrimeTimeout)
        if (emitReset && (reset || command != null)) {
            emitEvent(
                KundiNativeAvatarProtocol.event(
                    "presentationPrimingReset",
                    buildMap {
                        put("reason", reason)
                        put("surfaceGeneration", surfaceGeneration)
                        put("rendererId", rendererId)
                        command?.let {
                            put("rendererGeneration", it.rendererGeneration)
                            put("textureId", it.textureId)
                        }
                    },
                ),
            )
        }
    }

    private fun presentationPayload(
        command: NativeAvatarCommand.StartPresentationPriming,
        submittedFrameCount: Int,
        elapsedMillis: Long,
    ): Map<String, Any?> =
        mapOf(
            "rendererGeneration" to command.rendererGeneration,
            "textureId" to command.textureId,
            "surfaceGeneration" to surfaceGeneration,
            "submittedFrameCount" to submittedFrameCount,
            "elapsedMillis" to elapsedMillis,
            "rendererId" to rendererId,
            "modelId" to modelSha256.take(16),
        )

    private fun setEmotion(emotion: String) {
        KundiNativeAvatarProtocol.emotionBlendShapes.values.forEach(faceWeights::remove)
        faceWeights[checkNotNull(KundiNativeAvatarProtocol.emotionBlendShapes[emotion])] = 1f
        applyFaceWeights()
        emitFaceState("emotion", emotion)
    }

    private fun setViseme(viseme: String) {
        KundiNativeAvatarProtocol.visemeBlendShapes.values.forEach(faceWeights::remove)
        faceWeights[checkNotNull(KundiNativeAvatarProtocol.visemeBlendShapes[viseme])] = 1f
        applyFaceWeights()
        emitFaceState("viseme", viseme)
    }

    private fun blink() {
        mainHandler.removeCallbacks(blinkReset)
        blinkWeight = 1f
        applyFaceWeights()
        emitFaceState("blink", blinkBlendShape)
        mainHandler.postDelayed(blinkReset, blinkDurationMillis)
    }

    private fun resetFace() {
        mainHandler.removeCallbacks(blinkReset)
        blinkWeight = 0f
        faceWeights.clear()
        applyFaceWeights()
        emitFaceState("reset", "neutral")
    }

    private fun emitFaceState(
        mode: String,
        value: String,
    ) {
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "faceStateChanged",
                mapOf(
                    "mode" to mode,
                    "value" to value,
                    "renderableBindings" to morphBindings.size,
                ),
            ),
        )
    }

    private fun applyFaceWeights() {
        if (!modelReady || disposed) return
        val renderableManager = engine.renderableManager
        morphBindings.forEach { (entity, bindings) ->
            val instance = renderableManager.getInstance(entity)
            if (instance == 0) return@forEach
            val weights = FloatArray(renderableManager.getMorphTargetCount(instance))
            bindings.forEach { (name, index) ->
                weights[index] =
                    if (name == blinkBlendShape) {
                        max(blinkWeight, faceWeights[name] ?: 0f)
                    } else {
                        faceWeights[name] ?: 0f
                    }
            }
            renderableManager.setMorphWeights(instance, weights, 0)
        }
    }

    private fun onCadenceModeChanged(mode: KundiAvatarCadenceMode) {
        frameLoop.resetCadenceDeadline()
        metricsWindowStartedNanos = 0L
        lastFrameNanos = 0L
        frameCount = 0
        frameTimeSumNanos = 0L
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "cadenceChanged",
                mapOf(
                    "mode" to mode.wireName,
                    "targetFps" to mode.targetFps,
                    "frameCallbacksPosted" to frameCallbackPostedCount,
                    "frameCallbacksReceived" to frameCallbackCount,
                    "renderedFrames" to renderedFrameCount,
                ),
            ),
        )
        if (mode.targetFps == 0) {
            stopFrames()
        } else {
            scheduleFrame()
        }
    }

    private fun resumeIfPossible() {
        if (!attached || !hostResumed || disposed) return
        if (!requestedVisible) return
        if (lifecycle.resume()) {
            emitLifecycle("running")
        }
        scheduleFrame()
    }

    private fun scheduleFrame() {
        if (frameScheduled || !shouldRender()) return
        frameScheduled = true
        frameCallbackPostedCount++
        choreographer.postFrameCallback(this)
    }

    private fun stopFrames() {
        if (frameScheduled) {
            choreographer.removeFrameCallback(this)
            frameScheduled = false
        }
        frameLoop.resetCadenceDeadline()
    }

    private fun shouldRender(): Boolean =
        !disposed &&
            attached &&
            hostResumed &&
            requestedVisible &&
            frameLoop.canSchedule(
                targetFps = cadence.targetFps,
                oneShotPending = restorationFramePending,
            ) &&
            lifecycle.state == RendererLifecycleState.RUNNING

    private fun reportFatalRendererError(
        error: Throwable,
        code: String,
        fallbackMessage: String,
    ) {
        if (!frameLoop.markFatalError()) return
        resetPresentationPriming(reason = "renderer_error", emitReset = false)
        commandsPendingModelLoad.clear()
        cadence.freeze()
        stopFrames()
        Log.e("KundiNativeAvatar", fallbackMessage, error)
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "rendererError",
                mapOf(
                    "code" to code,
                    "message" to (error.message ?: fallbackMessage),
                ),
            ),
        )
    }

    private fun emitLifecycle(status: String) {
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "lifecycle",
                mapOf("status" to status),
            ),
        )
    }

    private fun recordFrameMetrics(
        frameTimeNanos: Long,
        rendered: Boolean,
    ) {
        if (!rendered) return
        if (metricsWindowStartedNanos == 0L) {
            metricsWindowStartedNanos = frameTimeNanos
            lastFrameNanos = frameTimeNanos
            return
        }
        frameCount++
        frameTimeSumNanos += frameTimeNanos - lastFrameNanos
        lastFrameNanos = frameTimeNanos
        val windowNanos = frameTimeNanos - metricsWindowStartedNanos
        if (windowNanos < metricsWindowNanos || frameCount == 0) return

        val fps = frameCount * 1_000_000_000.0 / windowNanos
        val frameMillis = frameTimeSumNanos / frameCount / 1_000_000.0
        emitEvent(
            KundiNativeAvatarProtocol.event(
                "frameMetrics",
                mapOf(
                    "fps" to String.format(Locale.US, "%.2f", fps).toDouble(),
                    "frameTimeMs" to
                        String.format(Locale.US, "%.2f", frameMillis).toDouble(),
                ),
            ),
        )
        metricsWindowStartedNanos = frameTimeNanos
        frameCount = 0
        frameTimeSumNanos = 0L
    }

    private data class AnimationMetadata(
        val index: Int,
        val durationSeconds: Float,
    )

    private data class AnimationPlayback(
        val name: String,
        val metadata: AnimationMetadata,
        val loop: Boolean,
        val startedNanos: Long,
    ) {
        fun elapsedSeconds(nowNanos: Long): Float =
            ((nowNanos - startedNanos).coerceAtLeast(0L) / 1_000_000_000.0).toFloat()
    }

    private data class PreviousAnimation(
        val index: Int,
        val timeSeconds: Float,
    )

    private data class FixedAnimationSample(
        val index: Int,
        val timeSeconds: Float,
    )

    private companion object {
        val rendererIds = AtomicLong(0L)
        const val expectedSkinCount = 1
        const val expectedJointCount = 153
        const val expectedMeshCount = 3
        const val expectedMaterialCount = 6
        const val blinkBlendShape = "Fcl_EYE_Close"
        const val blinkDurationMillis = 140L
        const val crossFadeDurationNanos = 180_000_000.0
        const val metricsWindowNanos = 1_000_000_000L
        const val nearPlane = 0.1
        const val farPlane = 100.0
    }
}
