import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/lessons/presentation/widgets/kundi_home_hero.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_home_avatar_loading_frame.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_home_avatar_placement.dart';

void main() {
  test('WebP remains visible until the first realtime frame', () {
    expect(
      kundiHomeRealtimeFrameVisible(
        realtimeEnabled: true,
        revealReady: false,
        rendererFailed: false,
      ),
      isFalse,
    );
  });

  test('renderer error restores the WebP fallback', () {
    expect(
      kundiHomeRealtimeFrameVisible(
        realtimeEnabled: true,
        revealReady: true,
        rendererFailed: true,
      ),
      isFalse,
    );
  });

  test('successful first frame replaces WebP only when feature is enabled', () {
    expect(
      kundiHomeRealtimeFrameVisible(
        realtimeEnabled: true,
        revealReady: true,
        rendererFailed: false,
      ),
      isTrue,
    );
    expect(
      kundiHomeRealtimeFrameVisible(
        realtimeEnabled: false,
        revealReady: true,
        rendererFailed: false,
      ),
      isFalse,
    );
  });

  test('pending runtime has a loading layer before a renderer exists', () {
    final state = KundiHomeAvatarTransitionState();

    expect(
      state.staticLayer(
        realtimePreparing: true,
        realtimeEnabled: false,
      ),
      KundiHomeAvatarStaticLayer.loading,
    );
  });

  test('retained renderer return keeps the first frame and skips loading', () {
    final state = KundiHomeAvatarTransitionState()..beginRendererSession();
    expect(state.markRevealReady(), isTrue);
    expect(state.markHandoffCompleted(), isTrue);

    expect(state.revealReady, isTrue);
    expect(state.crossfadeCompleted, isTrue);
    expect(state.rendererSessionActive, isTrue);
    expect(
      kundiHomeRealtimeFrameVisible(
        realtimeEnabled: true,
        revealReady: state.revealReady,
        rendererFailed: state.rendererFailed,
      ),
      isTrue,
    );
  });

  test('crossfade happens once per renderer session', () {
    final state = KundiHomeAvatarTransitionState()..beginRendererSession();

    expect(state.markRevealReady(), isTrue);
    expect(state.markRevealReady(), isFalse);
    expect(state.markHandoffCompleted(), isTrue);
    expect(state.markHandoffCompleted(), isFalse);

    state.markRendererDisposed();
    state.beginRendererSession();

    expect(state.markRevealReady(), isTrue);
  });

  test('renderer failure selects the fatal WebP fallback', () {
    final state = KundiHomeAvatarTransitionState()..beginRendererSession();
    state.markRendererFailed();

    expect(
      state.staticLayer(
        realtimePreparing: false,
        realtimeEnabled: true,
      ),
      KundiHomeAvatarStaticLayer.fatalFallback,
    );
  });

  testWidgets('pending eligibility hides WebP behind an opaque loading layer',
      (tester) async {
    final loadingImage = await _testImage(Colors.purple);
    final fallbackImage = await _testImage(Colors.blue);
    final preparedFrame = KundiHomeAvatarLoadingFrame(
      primaryImage: loadingImage,
      fatalFallbackImage: fallbackImage,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KundiHomeHero(
            title: 'Привет',
            dateLabel: 'Сегодня',
            message: 'Проверяем первый кадр.',
            assetPath: 'assets/images/kundi/home/kundi_home.webp',
            realtimeAvatarPreparing: true,
            preparedLoadingFrame: preparedFrame,
          ),
        ),
      ),
    );

    expect(
        find.byKey(KundiHomeAvatarPlacement.loadingAssetKey), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    expect(find.byKey(KundiHomeHero.assetKey), findsNothing);

    await tester.pumpWidget(const SizedBox());
    preparedFrame.dispose();
  });

  testWidgets('Texture stays mounted below the opaque loading layer',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 160,
          height: 220,
          child: KundiHomeAvatarLayerStack(
            revealReady: false,
            realtimeLayer: Texture(textureId: 42),
            staticLayer: ColoredBox(color: Colors.purple),
          ),
        ),
      ),
    );

    final stack = tester.widget<Stack>(
      find.byKey(KundiHomeAvatarLayerStack.stackKey),
    );
    expect(
        stack.children.first.key, KundiHomeAvatarLayerStack.realtimeLayerKey);
    expect(
      find.ancestor(
        of: find.byType(Texture),
        matching: find.byType(AnimatedOpacity),
      ),
      findsNothing,
    );
    final loadingOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(KundiHomeAvatarLayerStack.staticOpacityKey),
    );
    expect(loadingOpacity.opacity, 1);
    expect(loadingOpacity.duration, Duration.zero);
  });

  testWidgets('only the prepared loading layer fades after reveal-ready',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 160,
          height: 220,
          child: KundiHomeAvatarLayerStack(
            revealReady: true,
            realtimeLayer: Texture(textureId: 42),
            staticLayer: ColoredBox(color: Colors.purple),
          ),
        ),
      ),
    );

    final loadingOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(KundiHomeAvatarLayerStack.staticOpacityKey),
    );
    expect(loadingOpacity.opacity, 0);
    expect(
      loadingOpacity.duration,
      KundiHomeAvatarPlacement.loadingCrossfadeDuration,
    );
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('loading layer is removed only after handoff completes',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 160,
          height: 220,
          child: KundiHomeAvatarLayerStack(
            revealReady: true,
            handoffCompleted: true,
            realtimeLayer: Texture(textureId: 42),
            staticLayer: ColoredBox(color: Colors.purple),
          ),
        ),
      ),
    );

    expect(find.byType(Texture), findsOneWidget);
    expect(
      find.byKey(KundiHomeAvatarLayerStack.staticOpacityKey),
      findsNothing,
    );
  });
}

Future<ui.Image> _testImage(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 2, 2),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  picture.dispose();
  return image;
}
