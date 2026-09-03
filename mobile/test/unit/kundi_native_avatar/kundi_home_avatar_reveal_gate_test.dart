import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_home_avatar_diagnostics.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_home_avatar_reveal_gate.dart';

void main() {
  test('priming does not start before Texture mount and loading paint', () {
    final harness = _RevealHarness();
    final gate = harness.createGate();
    final generation = gate.beginSession(
      loadingImagePrepared: true,
      textureId: 42,
      textureMounted: false,
      modelLoaded: true,
    );

    gate.markLoadingLayerMounted(generation);
    gate.markLoadingLayerPainted(generation);
    expect(harness.primingRequests, isEmpty);

    gate.markTextureMounted(generation, 42);
    expect(harness.primingRequests, <String>['$generation:42']);
  });

  test('priming does not start before native model load', () {
    final harness = _RevealHarness();
    final gate = harness.createGate();
    final generation = gate.beginSession(
      loadingImagePrepared: true,
      textureId: 42,
      textureMounted: true,
      modelLoaded: false,
    );
    harness.markLoading(gate, generation);

    expect(harness.primingRequests, isEmpty);
    gate.markModelLoaded(generation);
    expect(harness.primingRequests, <String>['$generation:42']);
  });

  test('loading remains opaque until primed and one Flutter endOfFrame',
      () async {
    final harness = _RevealHarness();
    final gate = harness.createGate();
    final generation = harness.beginPriming(gate);

    gate.markPresentationPrimed(
      generation: generation,
      textureId: 42,
      submittedFrameCount: 22,
      elapsedMillis: 710,
    );
    await _flushMicrotasks();

    expect(gate.snapshot.presentationPrimed, isTrue);
    expect(gate.revealReady, isFalse);
    expect(harness.frameRequests, 1);

    harness.completeNextFrame();
    await _flushMicrotasks();
    expect(gate.revealReady, isTrue);
    expect(harness.revealedGenerations, <int>[generation]);
  });

  test('stale generation and mismatched Texture events are ignored', () async {
    final harness = _RevealHarness();
    final gate = harness.createGate();
    final staleGeneration = harness.beginPriming(gate);
    final currentGeneration = harness.beginPriming(gate);

    gate.markPresentationPrimed(
      generation: staleGeneration,
      textureId: 42,
      submittedFrameCount: 22,
      elapsedMillis: 710,
    );
    gate.markPresentationPrimed(
      generation: currentGeneration,
      textureId: 7,
      submittedFrameCount: 22,
      elapsedMillis: 710,
    );
    await _flushMicrotasks();

    expect(harness.frameRequests, 0);
    expect(gate.revealReady, isFalse);
  });

  test('surface recreation resets only the reveal generation', () async {
    final harness = _RevealHarness();
    final gate = harness.createGate();
    final firstGeneration = harness.beginPriming(gate);
    await harness.completeReveal(gate, firstGeneration);

    gate.invalidateSession();
    final secondGeneration = harness.beginPriming(gate);
    expect(gate.revealReady, isFalse);
    await harness.completeReveal(gate, secondGeneration);

    expect(
      harness.revealedGenerations,
      <int>[firstGeneration, secondGeneration],
    );
  });

  test('native priming timeout preserves loading and notifies once', () {
    final harness = _RevealHarness();
    final gate = harness.createGate();
    final generation = harness.beginPriming(gate);

    gate.markPresentationTimedOut(generation: generation, textureId: 42);
    gate.markPresentationTimedOut(generation: generation, textureId: 42);

    expect(gate.revealReady, isFalse);
    expect(gate.snapshot.presentationTimedOut, isTrue);
    expect(harness.timedOutGenerations, <int>[generation]);
  });

  test('failed endOfFrame preserves opaque loading', () async {
    final harness = _RevealHarness(frameFails: true);
    final gate = harness.createGate();
    final generation = harness.beginPriming(gate);

    gate.markPresentationPrimed(
      generation: generation,
      textureId: 42,
      submittedFrameCount: 22,
      elapsedMillis: 710,
    );
    await _flushMicrotasks();

    expect(gate.revealReady, isFalse);
    expect(harness.revealedGenerations, isEmpty);
  });

  test('typed diagnostics record priming before reveal', () async {
    final harness = _RevealHarness();
    final gate = harness.createGate();
    final generation = harness.beginPriming(gate);
    await harness.completeReveal(gate, generation);

    expect(
      harness.diagnostics,
      containsAllInOrder(<String>[
        KundiHomeAvatarTraceName.textureIdAvailable,
        KundiHomeAvatarTraceName.textureMounted,
        KundiHomeAvatarTraceName.loadingLayerPainted,
        KundiHomeAvatarTraceName.presentationPrimingRequested,
        KundiHomeAvatarTraceName.presentationPrimed,
        KundiHomeAvatarTraceName.revealGateOpened,
      ]),
    );
  });
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

final class _RevealHarness {
  _RevealHarness({this.frameFails = false});

  final bool frameFails;
  final Queue<Completer<void>> _frames = Queue<Completer<void>>();
  final List<String> primingRequests = <String>[];
  final List<int> revealedGenerations = <int>[];
  final List<int> timedOutGenerations = <int>[];
  final List<String> diagnostics = <String>[];
  int frameRequests = 0;

  KundiHomeAvatarRevealGate createGate() => KundiHomeAvatarRevealGate(
        waitForHandoffFrame: () {
          frameRequests++;
          if (frameFails) {
            return Future<void>.error(StateError('frame failed'));
          }
          final frame = Completer<void>();
          _frames.add(frame);
          return frame.future;
        },
        onPrimingRequested: (generation, textureId) {
          primingRequests.add('$generation:$textureId');
        },
        onRevealReady: revealedGenerations.add,
        onPresentationTimedOut: timedOutGenerations.add,
        recordDiagnostic: (
          name, {
          required generation,
          textureId,
          payload = const <String, Object?>{},
        }) {
          diagnostics.add(name);
        },
      );

  int beginPriming(KundiHomeAvatarRevealGate gate) {
    final generation = gate.beginSession(
      loadingImagePrepared: true,
      textureId: 42,
      textureMounted: true,
      modelLoaded: true,
    );
    markLoading(gate, generation);
    return generation;
  }

  void markLoading(KundiHomeAvatarRevealGate gate, int generation) {
    gate.markLoadingLayerMounted(generation);
    gate.markLoadingLayerPainted(generation);
  }

  void completeNextFrame() {
    expect(_frames, isNotEmpty);
    _frames.removeFirst().complete();
  }

  Future<void> completeReveal(
    KundiHomeAvatarRevealGate gate,
    int generation,
  ) async {
    gate.markPresentationPrimed(
      generation: generation,
      textureId: 42,
      submittedFrameCount: 22,
      elapsedMillis: 710,
    );
    await _flushMicrotasks();
    completeNextFrame();
    await _flushMicrotasks();
  }
}
