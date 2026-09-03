import 'dart:async';

import 'package:flutter/foundation.dart';

import 'kundi_home_avatar_diagnostics.dart';

typedef KundiHomeAvatarFrameBarrier = Future<void> Function();
typedef KundiHomeAvatarPrimingCallback = void Function(
  int generation,
  int textureId,
);
typedef KundiHomeAvatarRevealCallback = void Function(int generation);

@immutable
final class KundiHomeAvatarRevealSnapshot {
  const KundiHomeAvatarRevealSnapshot({
    required this.generation,
    required this.loadingImagePrepared,
    required this.loadingLayerMounted,
    required this.loadingLayerPainted,
    required this.textureIdAvailable,
    required this.textureWidgetMounted,
    required this.modelLoaded,
    required this.primingRequested,
    required this.presentationPrimed,
    required this.revealReady,
    required this.presentationTimedOut,
    required this.submittedFrameCount,
    required this.primingElapsedMillis,
    required this.textureId,
  });

  final int generation;
  final bool loadingImagePrepared;
  final bool loadingLayerMounted;
  final bool loadingLayerPainted;
  final bool textureIdAvailable;
  final bool textureWidgetMounted;
  final bool modelLoaded;
  final bool primingRequested;
  final bool presentationPrimed;
  final bool revealReady;
  final bool presentationTimedOut;
  final int submittedFrameCount;
  final int primingElapsedMillis;
  final int? textureId;
}

/// Coordinates Flutter-owned prerequisites and trusts only the native
/// successful-submission priming event to start the final handoff.
final class KundiHomeAvatarRevealGate {
  KundiHomeAvatarRevealGate({
    required KundiHomeAvatarFrameBarrier waitForHandoffFrame,
    required KundiHomeAvatarPrimingCallback onPrimingRequested,
    required KundiHomeAvatarRevealCallback onRevealReady,
    required KundiHomeAvatarRevealCallback onPresentationTimedOut,
    KundiHomeAvatarDiagnosticRecorder? recordDiagnostic,
  })  : _waitForHandoffFrame = waitForHandoffFrame,
        _onPrimingRequested = onPrimingRequested,
        _onRevealReady = onRevealReady,
        _onPresentationTimedOut = onPresentationTimedOut,
        _recordDiagnostic = recordDiagnostic;

  final KundiHomeAvatarFrameBarrier _waitForHandoffFrame;
  final KundiHomeAvatarPrimingCallback _onPrimingRequested;
  final KundiHomeAvatarRevealCallback _onRevealReady;
  final KundiHomeAvatarRevealCallback _onPresentationTimedOut;
  final KundiHomeAvatarDiagnosticRecorder? _recordDiagnostic;

  int _generation = 0;
  bool _sessionActive = false;
  bool _loadingImagePrepared = false;
  bool _loadingLayerMounted = false;
  bool _loadingLayerPainted = false;
  int? _textureId;
  bool _textureWidgetMounted = false;
  bool _modelLoaded = false;
  bool _primingRequested = false;
  bool _presentationPrimed = false;
  bool _handoffFrameScheduled = false;
  bool _revealReady = false;
  bool _presentationTimedOut = false;
  int _submittedFrameCount = 0;
  int _primingElapsedMillis = 0;
  bool _disposed = false;

  int get generation => _generation;
  bool get revealReady => _revealReady;

  KundiHomeAvatarRevealSnapshot get snapshot => KundiHomeAvatarRevealSnapshot(
        generation: _generation,
        loadingImagePrepared: _loadingImagePrepared,
        loadingLayerMounted: _loadingLayerMounted,
        loadingLayerPainted: _loadingLayerPainted,
        textureIdAvailable: _textureId != null,
        textureWidgetMounted: _textureWidgetMounted,
        modelLoaded: _modelLoaded,
        primingRequested: _primingRequested,
        presentationPrimed: _presentationPrimed,
        revealReady: _revealReady,
        presentationTimedOut: _presentationTimedOut,
        submittedFrameCount: _submittedFrameCount,
        primingElapsedMillis: _primingElapsedMillis,
        textureId: _textureId,
      );

  int beginSession({
    required bool loadingImagePrepared,
    required int? textureId,
    required bool textureMounted,
    required bool modelLoaded,
  }) {
    if (_disposed) return _generation;
    _generation++;
    _sessionActive = true;
    _loadingImagePrepared = loadingImagePrepared;
    _loadingLayerMounted = false;
    _loadingLayerPainted = false;
    _textureId = textureId;
    _textureWidgetMounted = textureMounted && textureId != null;
    _modelLoaded = modelLoaded;
    _primingRequested = false;
    _presentationPrimed = false;
    _handoffFrameScheduled = false;
    _revealReady = false;
    _presentationTimedOut = false;
    _submittedFrameCount = 0;
    _primingElapsedMillis = 0;
    if (textureId != null) {
      _record(KundiHomeAvatarTraceName.textureIdAvailable, _generation);
      if (_textureWidgetMounted) {
        _record(KundiHomeAvatarTraceName.textureMounted, _generation);
      }
    }
    _requestPrimingIfReady();
    return _generation;
  }

  void markLoadingLayerMounted(int generation) {
    if (!_isCurrent(generation)) return;
    _loadingLayerMounted = true;
    _requestPrimingIfReady();
  }

  void markLoadingLayerPainted(int generation) {
    if (!_isCurrent(generation)) return;
    _loadingLayerPainted = true;
    _record(KundiHomeAvatarTraceName.loadingLayerPainted, generation);
    _requestPrimingIfReady();
  }

  void markTextureIdAvailable(int generation, int textureId) {
    if (!_isCurrent(generation)) return;
    if (_textureId != null && _textureId != textureId) return;
    _textureId = textureId;
    _record(KundiHomeAvatarTraceName.textureIdAvailable, generation);
    _requestPrimingIfReady();
  }

  void markTextureMounted(int generation, int textureId) {
    if (!_isCurrent(generation) || _textureId != textureId) return;
    _textureWidgetMounted = true;
    _record(KundiHomeAvatarTraceName.textureMounted, generation);
    _requestPrimingIfReady();
  }

  void markModelLoaded(int generation) {
    if (!_isCurrent(generation)) return;
    _modelLoaded = true;
    _requestPrimingIfReady();
  }

  void markPresentationPrimed({
    required int generation,
    required int textureId,
    required int submittedFrameCount,
    required int elapsedMillis,
  }) {
    if (!_isCurrent(generation) ||
        _textureId != textureId ||
        !_primingRequested ||
        _presentationPrimed ||
        _presentationTimedOut) {
      return;
    }
    _presentationPrimed = true;
    _submittedFrameCount = submittedFrameCount;
    _primingElapsedMillis = elapsedMillis;
    _record(KundiHomeAvatarTraceName.presentationPrimed, generation);
    _scheduleHandoffFrame();
  }

  void markPresentationTimedOut({
    required int generation,
    required int textureId,
  }) {
    if (!_isCurrent(generation) ||
        _textureId != textureId ||
        !_primingRequested ||
        _presentationPrimed ||
        _presentationTimedOut) {
      return;
    }
    _presentationTimedOut = true;
    _record(KundiHomeAvatarTraceName.presentationPrimeTimedOut, generation);
    _onPresentationTimedOut(generation);
  }

  void invalidateSession() {
    if (_disposed) return;
    _generation++;
    _resetSession();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _resetSession();
  }

  void _resetSession() {
    _sessionActive = false;
    _loadingImagePrepared = false;
    _loadingLayerMounted = false;
    _loadingLayerPainted = false;
    _textureId = null;
    _textureWidgetMounted = false;
    _modelLoaded = false;
    _primingRequested = false;
    _presentationPrimed = false;
    _handoffFrameScheduled = false;
    _revealReady = false;
    _presentationTimedOut = false;
    _submittedFrameCount = 0;
    _primingElapsedMillis = 0;
  }

  void _requestPrimingIfReady() {
    if (!_baseConditionsReady || _primingRequested) return;
    final textureId = _textureId!;
    _primingRequested = true;
    _record(KundiHomeAvatarTraceName.presentationPrimingRequested, _generation);
    try {
      _onPrimingRequested(_generation, textureId);
    } on Object catch (error) {
      debugPrint(
        '[KUNDI_AVATAR_REVEAL] presentation priming request failed; '
        'loading preserved: $error',
      );
    }
  }

  void _scheduleHandoffFrame() {
    if (_handoffFrameScheduled || !_presentationPrimed) return;
    _handoffFrameScheduled = true;
    unawaited(_awaitHandoffFrame(_generation));
  }

  Future<void> _awaitHandoffFrame(int scheduledGeneration) async {
    try {
      await _waitForHandoffFrame();
      if (!_isCurrent(scheduledGeneration) ||
          !_presentationPrimed ||
          _presentationTimedOut) {
        return;
      }
      _revealReady = true;
      _record(KundiHomeAvatarTraceName.revealGateOpened, scheduledGeneration);
      _onRevealReady(scheduledGeneration);
    } on Object catch (error) {
      if (_isCurrent(scheduledGeneration)) {
        debugPrint(
          '[KUNDI_AVATAR_REVEAL] handoff frame failed; loading preserved: $error',
        );
      }
    }
  }

  bool get _baseConditionsReady =>
      !_disposed &&
      _sessionActive &&
      !_presentationTimedOut &&
      _loadingImagePrepared &&
      _loadingLayerMounted &&
      _loadingLayerPainted &&
      _textureId != null &&
      _textureWidgetMounted &&
      _modelLoaded;

  bool _isCurrent(int candidate) =>
      !_disposed && _sessionActive && candidate == _generation;

  void _record(String name, int generation) {
    _recordDiagnostic?.call(
      name,
      generation: generation,
      textureId: _textureId,
    );
  }
}
