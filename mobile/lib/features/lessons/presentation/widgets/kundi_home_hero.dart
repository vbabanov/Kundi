import 'dart:async';

import 'package:flutter/material.dart';
import '../../../assistant/application/kundi_tts_coordinator.dart';
import '../../../../runtimes/kundi_tts/kundi_tts_avatar_driver.dart';

import '../../../../runtimes/kundi_native_avatar/kundi_first_paint_notifier.dart';
import '../../../../runtimes/kundi_native_avatar/kundi_avatar_animation_policy.dart';
import '../../../../runtimes/kundi_native_avatar/kundi_home_avatar_diagnostics.dart';
import '../../../../runtimes/kundi_native_avatar/kundi_home_avatar_loading_frame.dart';
import '../../../../runtimes/kundi_native_avatar/kundi_home_avatar_placement.dart';
import '../../../../runtimes/kundi_native_avatar/kundi_home_avatar_reveal_gate.dart';
import '../../../../runtimes/kundi_native_avatar/kundi_native_avatar_controller.dart';
import '../../../../runtimes/kundi_native_avatar/kundi_native_avatar_protocol.dart';
import '../../../../runtimes/kundi_native_avatar/kundi_native_avatar_texture_view.dart';

bool kundiHomeRealtimeFrameVisible({
  required bool realtimeEnabled,
  required bool revealReady,
  required bool rendererFailed,
}) =>
    realtimeEnabled && revealReady && !rendererFailed;

enum KundiHomeAvatarStaticLayer { loading, fatalFallback }

final class KundiHomeAvatarTransitionState {
  bool revealReady = false;
  bool rendererFailed = false;
  bool _rendererSessionActive = false;
  bool _handoffCompleted = false;

  bool get rendererSessionActive => _rendererSessionActive;
  bool get handoffCompleted => _handoffCompleted;
  bool get crossfadeCompleted => _handoffCompleted;

  bool beginRendererSession() {
    if (_rendererSessionActive) return false;
    _rendererSessionActive = true;
    revealReady = false;
    rendererFailed = false;
    _handoffCompleted = false;
    return true;
  }

  bool markRevealReady() {
    if (rendererFailed || revealReady || _handoffCompleted) return false;
    revealReady = true;
    return true;
  }

  bool markHandoffCompleted() {
    if (!revealReady || rendererFailed || _handoffCompleted) return false;
    _handoffCompleted = true;
    return true;
  }

  void markRendererFailed() {
    revealReady = false;
    rendererFailed = true;
    _rendererSessionActive = false;
    _handoffCompleted = false;
  }

  void markRendererDisposed() {
    revealReady = false;
    rendererFailed = false;
    _rendererSessionActive = false;
    _handoffCompleted = false;
  }

  KundiHomeAvatarStaticLayer staticLayer({
    required bool realtimePreparing,
    required bool realtimeEnabled,
  }) {
    if (rendererFailed) return KundiHomeAvatarStaticLayer.fatalFallback;
    if (_rendererSessionActive || realtimePreparing || realtimeEnabled) {
      return KundiHomeAvatarStaticLayer.loading;
    }
    return KundiHomeAvatarStaticLayer.fatalFallback;
  }
}

class KundiHomeHero extends StatelessWidget {
  const KundiHomeHero({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.message,
    required this.assetPath,
    this.onAvatarTap,
    this.onAvatarPointerDown,
    this.onAvatarPointerUp,
    this.onAvatarPointerCancel,
    this.onAvatarLongPressStart,
    this.onAvatarLongPressEnd,
    this.onAvatarLongPressCancel,
    this.voiceStatusText = '',
    this.voiceListening = false,
    this.ttsState = const KundiTtsState(),
    this.semanticState,
    this.realtimeAvatarEnabled = false,
    this.realtimeAvatarPreparing = false,
    this.preparedLoadingFrame,
    this.isVisible = true,
    this.animationCueName = 'neutral',
    this.animationIdentity = 'home:neutral',
  });

  static const heroKey = Key('kundi-home-hero');
  static const assetKey = Key('kundi-home-hero-asset');

  final String title;
  final String dateLabel;
  final String message;
  final String assetPath;
  final VoidCallback? onAvatarTap;
  final PointerDownEventListener? onAvatarPointerDown;
  final PointerUpEventListener? onAvatarPointerUp;
  final PointerCancelEventListener? onAvatarPointerCancel;
  final GestureLongPressStartCallback? onAvatarLongPressStart;
  final GestureLongPressEndCallback? onAvatarLongPressEnd;
  final VoidCallback? onAvatarLongPressCancel;
  final String voiceStatusText;
  final bool voiceListening;
  final KundiTtsState ttsState;
  final String? semanticState;
  final bool realtimeAvatarEnabled;
  final bool realtimeAvatarPreparing;
  final KundiHomeAvatarLoadingFrame? preparedLoadingFrame;
  final bool isVisible;
  final String animationCueName;
  final String animationIdentity;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      label: semanticState,
      button: onAvatarTap != null,
      child: Container(
        key: heroKey,
        height: 280,
        clipBehavior: Clip.none,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xD91C174B), Color(0xD90D1238)],
          ),
          border: Border.all(color: const Color(0x806E5AD7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x334C35CF),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              right: 12,
              top: 45,
              child: _HeroGlow(),
            ),
            const Positioned(left: 22, top: 22, child: _Sparkle(size: 7)),
            const Positioned(left: 132, top: 56, child: _Sparkle(size: 4)),
            Positioned(
              left: 20,
              top: 28,
              right: 158,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    dateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFBEB3E6),
                          fontSize: 13,
                          height: 1.2,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFE5DFFF),
                          fontSize: 15,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: KundiHomeAvatarPlacement.slotRight,
              top: KundiHomeAvatarPlacement.slotTop,
              bottom: KundiHomeAvatarPlacement.slotBottom,
              width: KundiHomeAvatarPlacement.slotWidth,
              child: Listener(
                onPointerDown: onAvatarPointerDown,
                onPointerUp: onAvatarPointerUp,
                onPointerCancel: onAvatarPointerCancel,
                child: GestureDetector(
                  key: const Key('kundi-home-avatar-gesture'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onAvatarTap,
                  onLongPressStart: onAvatarLongPressStart,
                  onLongPressEnd: onAvatarLongPressEnd,
                  onLongPressCancel: onAvatarLongPressCancel,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: voiceListening
                          ? const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x4D58D8FF),
                                blurRadius: 9,
                                spreadRadius: 1,
                              ),
                            ]
                          : const <BoxShadow>[],
                    ),
                    child: _KundiHomeAvatar(
                      ttsState: ttsState,
                      assetPath: assetPath,
                      realtimeEnabled: realtimeAvatarEnabled,
                      realtimePreparing: realtimeAvatarPreparing,
                      preparedLoadingFrame: preparedLoadingFrame,
                      isVisible: isVisible,
                      animationCueName: animationCueName,
                      animationIdentity: animationIdentity,
                    ),
                  ),
                ),
              ),
            ),
            if (voiceStatusText.isNotEmpty)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  key: const Key('kundi-voice-status'),
                  constraints: const BoxConstraints(maxWidth: 230),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xE61B1746),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xAA58D8FF)),
                  ),
                  child: Text(
                    voiceStatusText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return content;
  }
}

class _KundiHomeAvatar extends StatefulWidget {
  const _KundiHomeAvatar({
    required this.ttsState,
    required this.assetPath,
    required this.realtimeEnabled,
    required this.realtimePreparing,
    required this.preparedLoadingFrame,
    required this.isVisible,
    required this.animationCueName,
    required this.animationIdentity,
  });

  final KundiTtsState ttsState;
  final String assetPath;
  final bool realtimeEnabled;
  final bool realtimePreparing;
  final KundiHomeAvatarLoadingFrame? preparedLoadingFrame;
  final bool isVisible;
  final String animationCueName;
  final String animationIdentity;

  @override
  State<_KundiHomeAvatar> createState() => _KundiHomeAvatarState();
}

class _KundiHomeAvatarState extends State<_KundiHomeAvatar> {
  final _ttsDriver = KundiTtsAvatarDriver();
  static const Duration _greetingDuration = Duration(milliseconds: 2600);

  KundiNativeAvatarController? _controller;
  StreamSubscription<KundiNativeAvatarEvent>? _events;
  bool _modelReady = false;
  bool _renderSurfaceMounted = false;
  int? _renderSurfaceId;
  int? _activeRendererGeneration;
  final KundiHomeAvatarTransitionState _transition =
      KundiHomeAvatarTransitionState();
  late final KundiHomeAvatarRevealGate _revealGate;
  late final KundiHomeAvatarLifecycleTelemetry _lifecycleTelemetry =
      KundiHomeAvatarLifecycleTelemetry(
    recordDiagnostic: KundiHomeAvatarDiagnostics.instance.record,
  );
  Timer? _greetingTimer;
  String? _playedGreetingIdentity;

  @override
  void initState() {
    super.initState();
    _revealGate = KundiHomeAvatarRevealGate(
      waitForHandoffFrame: () => WidgetsBinding.instance.endOfFrame,
      onPrimingRequested: _onPrimingRequested,
      onRevealReady: _onRevealReady,
      onPresentationTimedOut: _onPresentationTimedOut,
      recordDiagnostic: KundiHomeAvatarDiagnostics.instance.record,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      KundiHomeAvatarDiagnostics.instance.record(
        KundiHomeAvatarTraceName.homeHeroMounted,
        generation: _activeRendererGeneration ?? 0,
        textureId: _renderSurfaceId,
      );
    });
  }

  @override
  void didUpdateWidget(covariant _KundiHomeAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ttsState != widget.ttsState &&
        (oldWidget.ttsState.active || widget.ttsState.active)) {
      _greetingTimer?.cancel();
      if (_modelReady &&
          _transition.handoffCompleted &&
          widget.isVisible &&
          _controller != null) {
        unawaited(_ttsDriver.apply(_controller!, widget.ttsState));
      }
    }
    if (oldWidget.isVisible && !widget.isVisible) {
      _completeActiveGreeting(KundiGreetingCompletionReason.cancelled);
    } else if (oldWidget.animationCueName != widget.animationCueName ||
        oldWidget.animationIdentity != widget.animationIdentity) {
      _completeActiveGreeting(KundiGreetingCompletionReason.interrupted);
    }
    if (oldWidget.isVisible != widget.isVisible) {
      unawaited(_controller?.setVisible(widget.isVisible));
    }
    if (oldWidget.animationCueName != widget.animationCueName ||
        oldWidget.animationIdentity != widget.animationIdentity ||
        oldWidget.isVisible != widget.isVisible) {
      unawaited(_applyCue());
    }
  }

  @override
  void dispose() {
    _ttsDriver.invalidate();
    _completeActiveGreeting(KundiGreetingCompletionReason.cancelled);
    _greetingTimer?.cancel();
    unawaited(_events?.cancel());
    unawaited(_controller?.dispose());
    _revealGate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showRealtime = kundiHomeRealtimeFrameVisible(
      realtimeEnabled: widget.realtimeEnabled,
      revealReady: _transition.revealReady,
      rendererFailed: _transition.rendererFailed,
    );
    final staticLayer = _transition.staticLayer(
      realtimePreparing: widget.realtimePreparing,
      realtimeEnabled: widget.realtimeEnabled,
    );
    final showLoading = staticLayer == KundiHomeAvatarStaticLayer.loading;
    final preparedFrame = widget.preparedLoadingFrame;
    final Widget staticAvatar;
    if (showLoading) {
      // The production GLB path must never present a static character as its
      // normal state. This transparent paint barrier preserves the safe
      // handoff without flashing the WebP fallback while Filament initializes.
      staticAvatar = KundiFirstPaintNotifier(
        generation: _activeRendererGeneration ?? 0,
        onMounted: _onLoadingLayerMounted,
        onPainted: _onLoadingLayerPainted,
        child: const SizedBox.expand(
          key: KundiHomeAvatarPlacement.loadingAssetKey,
        ),
      );
    } else if (_transition.rendererFailed && preparedFrame != null) {
      staticAvatar = RawImage(
        image: preparedFrame.fatalFallbackImage,
        key: KundiHomeHero.assetKey,
        fit: BoxFit.contain,
        alignment: Alignment.bottomRight,
        filterQuality: FilterQuality.high,
      );
    } else {
      staticAvatar = Image.asset(
        widget.assetPath,
        key: KundiHomeHero.assetKey,
        fit: BoxFit.contain,
        alignment: Alignment.bottomRight,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Персонаж Kundi',
      );
    }
    return KundiHomeAvatarLayerStack(
      revealReady: showRealtime,
      handoffCompleted: _transition.handoffCompleted,
      onStaticFadeCompleted: _onStaticFadeCompleted,
      realtimeLayer: widget.realtimeEnabled
          ? ExcludeSemantics(
              child: IgnorePointer(
                child: KundiNativeAvatarTextureView(
                  onControllerCreated: _onControllerCreated,
                  onTextureAvailable: _onRenderSurfaceAvailable,
                  onTextureMounted: _onRenderSurfaceMounted,
                  onRendererError: _onRendererCreationError,
                ),
              ),
            )
          : null,
      staticLayer: Semantics(
        label: 'Персонаж Kundi',
        image: true,
        child: staticAvatar,
      ),
    );
  }

  void _onControllerCreated(KundiNativeAvatarController controller) {
    _ttsDriver.invalidate();
    final previousController = _controller;
    if (previousController != null &&
        !identical(previousController, controller)) {
      unawaited(previousController.dispose());
    }
    unawaited(_events?.cancel());
    _controller = controller;
    setState(() => _beginRendererSession(force: true));
    _events = controller.events.listen((event) {
      if (identical(_controller, controller)) {
        _onEvent(event);
      }
    });
    unawaited(controller.setVisible(widget.isVisible));
  }

  void _onRenderSurfaceAvailable(int? surfaceId) {
    if (!mounted || surfaceId == null) return;
    _renderSurfaceId = surfaceId;
    _renderSurfaceMounted = false;
    final generation = _activeRendererGeneration;
    if (generation != null) {
      _revealGate.markTextureIdAvailable(generation, surfaceId);
    }
  }

  void _onRenderSurfaceMounted(int? surfaceId) {
    if (!mounted || surfaceId == null || surfaceId != _renderSurfaceId) return;
    _renderSurfaceMounted = true;
    final generation = _activeRendererGeneration;
    if (generation != null) {
      _revealGate.markTextureMounted(generation, surfaceId);
    }
  }

  void _onLoadingLayerMounted(int generation) {
    if (!mounted || generation != _activeRendererGeneration) return;
    _revealGate.markLoadingLayerMounted(generation);
  }

  void _onLoadingLayerPainted(int generation) {
    if (!mounted || generation != _activeRendererGeneration) return;
    _revealGate.markLoadingLayerPainted(generation);
  }

  void _onRendererCreationError() {
    if (!mounted) return;
    setState(() {
      _modelReady = false;
      _transition.markRendererFailed();
      _activeRendererGeneration = null;
      _revealGate.invalidateSession();
    });
  }

  void _onEvent(KundiNativeAvatarEvent event) {
    switch (event.name) {
      case 'rendererReady':
        if (mounted) {
          setState(() {
            _modelReady = false;
            _beginRendererSession();
          });
        }
      case 'modelLoading':
        if (mounted) {
          setState(() {
            _modelReady = false;
          });
        }
      case 'modelLoaded':
        _modelReady = true;
        final generation = _activeRendererGeneration;
        if (generation != null) {
          _revealGate.markModelLoaded(generation);
        }
      case 'firstFrame':
        final generation = _activeRendererGeneration;
        if (mounted && generation != null) {
          KundiHomeAvatarDiagnostics.instance.record(
            KundiHomeAvatarTraceName.nativeFirstFrame,
            generation: generation,
            textureId: _renderSurfaceId,
          );
        }
      case 'presentationPrimed':
        _handlePresentationPrimed(event);
      case 'presentationPrimeTimedOut':
        _handlePresentationPrimeTimedOut(event);
      case 'surfaceCleanup':
        if (mounted && _transition.rendererSessionActive) {
          setState(() => _beginRendererSession(force: true));
        }
      case 'restPoseFrameRendered':
        final generation = _activeRendererGeneration;
        if (generation != null) {
          KundiHomeAvatarDiagnostics.instance.record(
            KundiHomeAvatarTraceName.standingFrozen,
            generation: generation,
            textureId: _renderSurfaceId,
          );
        }
      case 'rendererError':
        if (mounted) {
          final generation = _activeRendererGeneration;
          if (generation != null) {
            _lifecycleTelemetry.suppressGeneration(generation);
          }
          setState(() {
            _modelReady = false;
            _transition.markRendererFailed();
            _activeRendererGeneration = null;
            _revealGate.invalidateSession();
          });
        }
      case 'rendererDisposed':
        if (mounted) {
          _completeActiveGreeting(KundiGreetingCompletionReason.cancelled);
          setState(() {
            _modelReady = false;
            _transition.markRendererDisposed();
            _activeRendererGeneration = null;
            _revealGate.invalidateSession();
          });
        }
    }
  }

  void _beginRendererSession({bool force = false}) {
    if (force) {
      _completeActiveGreeting(KundiGreetingCompletionReason.cancelled);
      final previousGeneration = _activeRendererGeneration;
      if (previousGeneration != null) {
        _lifecycleTelemetry.suppressGeneration(previousGeneration);
      }
      _transition.markRendererDisposed();
      _revealGate.invalidateSession();
    }
    if (!_transition.beginRendererSession()) return;
    _activeRendererGeneration = _revealGate.beginSession(
      // The realtime path always paints an explicit transparent loading
      // barrier. A decoded bitmap is optional and is retained only for the
      // fatal fallback, so it must not gate Filament presentation priming.
      loadingImagePrepared:
          widget.realtimeEnabled || widget.preparedLoadingFrame != null,
      textureId: _renderSurfaceId,
      textureMounted: _renderSurfaceMounted,
      modelLoaded: _modelReady,
    );
    _lifecycleTelemetry.beginGeneration(_activeRendererGeneration!);
  }

  void _onPrimingRequested(int generation, int textureId) {
    final controller = _controller;
    if (controller == null || generation != _activeRendererGeneration) return;
    unawaited(
      controller
          .startPresentationPriming(
            rendererGeneration: generation,
            textureId: textureId,
          )
          .catchError((Object _) => _onPresentationTimedOut(generation)),
    );
  }

  void _handlePresentationPrimed(KundiNativeAvatarEvent event) {
    final generation = _payloadInt(event, 'rendererGeneration');
    final textureId = _payloadInt(event, 'textureId');
    final submittedFrames = _payloadInt(event, 'submittedFrameCount');
    final elapsedMillis = _payloadInt(event, 'elapsedMillis');
    if (generation == null ||
        textureId == null ||
        submittedFrames == null ||
        elapsedMillis == null) {
      return;
    }
    _revealGate.markPresentationPrimed(
      generation: generation,
      textureId: textureId,
      submittedFrameCount: submittedFrames,
      elapsedMillis: elapsedMillis,
    );
  }

  void _handlePresentationPrimeTimedOut(KundiNativeAvatarEvent event) {
    final generation = _payloadInt(event, 'rendererGeneration');
    final textureId = _payloadInt(event, 'textureId');
    if (generation == null || textureId == null) return;
    _revealGate.markPresentationTimedOut(
      generation: generation,
      textureId: textureId,
    );
  }

  int? _payloadInt(KundiNativeAvatarEvent event, String name) {
    final value = event.payload[name];
    return value is num ? value.toInt() : null;
  }

  void _onRevealReady(int generation) {
    if (!mounted || generation != _activeRendererGeneration) return;
    if (_transition.markRevealReady()) {
      final snapshot = _revealGate.snapshot;
      KundiHomeAvatarDiagnostics.instance.record(
        KundiHomeAvatarTraceName.loadingFadeStarted,
        generation: generation,
        textureId: _renderSurfaceId,
      );
      debugPrint(
        '[KUNDI_AVATAR_REVEAL] generation=$generation ready '
        'after ${snapshot.submittedFrameCount} successful native frames and '
        '${snapshot.primingElapsedMillis}ms',
      );
      setState(() {});
    }
  }

  void _onPresentationTimedOut(int generation) {
    if (!mounted || generation != _activeRendererGeneration) return;
    _lifecycleTelemetry.suppressGeneration(generation);
    unawaited(_controller?.setVisible(false));
    setState(() {
      _modelReady = false;
      _transition.markRendererFailed();
      _activeRendererGeneration = null;
      _revealGate.invalidateSession();
    });
  }

  void _onStaticFadeCompleted() {
    final generation = _activeRendererGeneration;
    if (!mounted || generation == null || !_transition.revealReady) return;
    KundiHomeAvatarDiagnostics.instance.record(
      KundiHomeAvatarTraceName.loadingFadeCompleted,
      generation: generation,
      textureId: _renderSurfaceId,
    );
    if (_transition.markHandoffCompleted()) {
      const duration = KundiHomeAvatarPlacement.loadingCrossfadeDuration;
      _lifecycleTelemetry.recordHandoffCompleted(
        generation: generation,
        textureId: _renderSurfaceId,
        mode: duration == Duration.zero ? 'instant' : 'fade',
        durationMs: duration.inMilliseconds,
      );
      setState(() {});
      unawaited(_applyCue());
    }
  }

  Future<void> _applyCue() async {
    try {
      await _applyCueUnchecked();
    } on Object {
      if (mounted) {
        final generation = _activeRendererGeneration;
        if (generation != null) {
          _lifecycleTelemetry.suppressGeneration(generation);
        }
        setState(() {
          _modelReady = false;
          _transition.markRendererFailed();
          _activeRendererGeneration = null;
          _revealGate.invalidateSession();
        });
      }
    }
  }

  Future<void> _applyCueUnchecked() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    await controller.setVisible(widget.isVisible);
    if (!_modelReady || !widget.isVisible || !_transition.handoffCompleted) {
      return;
    }
    if (widget.ttsState.active) {
      _greetingTimer?.cancel();
      await _ttsDriver.apply(controller, widget.ttsState);
      return;
    }
    _ttsDriver.invalidate();
    await controller.resetFace();
    final decision = KundiAvatarAnimationPolicy.resolve(
      cueName: widget.animationCueName,
      identity: widget.animationIdentity,
    );
    switch (decision.target) {
      case KundiAvatarAnimationTarget.dansing:
        await controller.setEmotion(KundiNativeAvatarEmotion.joy);
        await controller.playCelebration();
      case KundiAvatarAnimationTarget.waiting:
        await controller.setEmotion(KundiNativeAvatarEmotion.neutral);
        await controller.playWaiting();
      case KundiAvatarAnimationTarget.idle:
        await controller.setEmotion(KundiNativeAvatarEmotion.neutral);
        await controller.playIdle();
      case KundiAvatarAnimationTarget.talking:
        await controller.setEmotion(KundiNativeAvatarEmotion.neutral);
        await controller.playTalking(decision.talkingVariant!);
      case KundiAvatarAnimationTarget.standing:
        await controller.setEmotion(KundiNativeAvatarEmotion.neutral);
        if (widget.animationIdentity.startsWith('home:greeting:') &&
            _playedGreetingIdentity != widget.animationIdentity) {
          _playedGreetingIdentity = widget.animationIdentity;
          final variant = KundiAvatarAnimationPolicy.talkingVariant(
            widget.animationIdentity,
          );
          final generation = _activeRendererGeneration;
          if (generation != null) {
            _lifecycleTelemetry.startGreeting(
              generation: generation,
              textureId: _renderSurfaceId,
              identity: widget.animationIdentity,
              animationName: 'Talking$variant',
              durationMs: _greetingDuration.inMilliseconds,
            );
          }
          await controller.playTalking(variant);
          _greetingTimer?.cancel();
          _greetingTimer = Timer(_greetingDuration, () {
            if (mounted &&
                widget.isVisible &&
                widget.animationCueName == 'neutral' &&
                _playedGreetingIdentity == widget.animationIdentity) {
              final activeGeneration = _activeRendererGeneration;
              if (activeGeneration != null) {
                _lifecycleTelemetry.completeGreeting(
                  generation: activeGeneration,
                  textureId: _renderSurfaceId,
                  identity: widget.animationIdentity,
                  reason: KundiGreetingCompletionReason.finished,
                );
              }
              unawaited(_transitionGreetingToRest(controller));
            }
          });
        } else {
          await controller.settleRestPose();
        }
    }
  }

  Future<void> _transitionGreetingToRest(
    KundiNativeAvatarController controller,
  ) async {
    if (!mounted ||
        !widget.isVisible ||
        widget.animationCueName != 'neutral' ||
        _playedGreetingIdentity != widget.animationIdentity) {
      return;
    }
    await controller.settleRestPose();
  }

  void _completeActiveGreeting(KundiGreetingCompletionReason reason) {
    final generation = _activeRendererGeneration;
    final identity = _playedGreetingIdentity;
    if (generation == null || identity == null) return;
    _lifecycleTelemetry.completeGreeting(
      generation: generation,
      textureId: _renderSurfaceId,
      identity: identity,
      reason: reason,
    );
  }
}

@visibleForTesting
class KundiHomeAvatarLayerStack extends StatelessWidget {
  const KundiHomeAvatarLayerStack({
    required this.revealReady,
    required this.staticLayer,
    this.handoffCompleted = false,
    this.realtimeLayer,
    this.onStaticFadeCompleted,
    super.key,
  });

  static const stackKey = Key('kundi-home-avatar-layer-stack');
  static const realtimeLayerKey = Key('kundi-home-avatar-realtime-layer');
  static const staticOpacityKey = Key('kundi-home-avatar-static-opacity');

  final bool revealReady;
  final bool handoffCompleted;
  final Widget staticLayer;
  final Widget? realtimeLayer;
  final VoidCallback? onStaticFadeCompleted;

  @override
  Widget build(BuildContext context) {
    final realtime = realtimeLayer;
    return Stack(
      key: stackKey,
      fit: StackFit.expand,
      children: [
        if (realtime != null)
          KeyedSubtree(key: realtimeLayerKey, child: realtime),
        if (!handoffCompleted)
          AnimatedOpacity(
            key: staticOpacityKey,
            opacity: revealReady ? 0 : 1,
            duration: revealReady
                ? KundiHomeAvatarPlacement.loadingCrossfadeDuration
                : Duration.zero,
            onEnd: revealReady ? onStaticFadeCompleted : null,
            child: staticLayer,
          ),
      ],
    );
  }
}

class _HeroGlow extends StatelessWidget {
  const _HeroGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 180,
        height: 180,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x668B5CF6),
              blurRadius: 72,
              spreadRadius: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: 0.78,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFD7C8FF),
            borderRadius: BorderRadius.circular(1),
            boxShadow: const [
              BoxShadow(color: Color(0xFF8B5CF6), blurRadius: 8),
            ],
          ),
        ),
      ),
    );
  }
}
