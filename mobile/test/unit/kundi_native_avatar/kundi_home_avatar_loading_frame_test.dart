import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_home_avatar_loading_frame.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_home_avatar_placement.dart';

void main() {
  testWidgets('primary failure selects a real decoded fatal fallback',
      (tester) async {
    final fallback = await _testImage(Colors.purple);
    final decoded = <String>[];
    final preloader = KundiHomeAvatarLoadingFramePreloader(
      decodeFrame: (assetPath) async {
        decoded.add(assetPath);
        if (assetPath == KundiHomeAvatarPlacement.loadingAssetPath) {
          throw StateError('primary decode failed');
        }
        return fallback;
      },
    );

    final frame = await preloader.prepare();

    expect(frame.usesFatalFallback, isTrue);
    expect(frame.primaryFrameReady, isFalse);
    expect(frame.fatalFallbackReady, isTrue);
    expect(identical(frame.loadingImage, fallback), isTrue);
    expect(decoded, <String>[
      KundiHomeAvatarPlacement.loadingAssetPath,
      KundiHomeAvatarPlacement.fatalFallbackAssetPath,
    ]);
    frame.dispose();
  });

  testWidgets('preparation is retained and decode runs once per asset',
      (tester) async {
    var decodeCalls = 0;
    final images = <ui.Image>[];
    final preloader = KundiHomeAvatarLoadingFramePreloader(
      decodeFrame: (_) async {
        decodeCalls++;
        final image = await _testImage(Colors.blue);
        images.add(image);
        return image;
      },
    );

    final firstPreparation = preloader.prepare();
    final secondPreparation = preloader.prepare();
    final first = await firstPreparation;
    final second = await secondPreparation;

    expect(identical(firstPreparation, secondPreparation), isTrue);
    expect(identical(first, second), isTrue);
    expect(decodeCalls, 2, reason: 'primary and fatal decode exactly once');
    expect(first.primaryFrameReady, isTrue);
    expect(first.fatalFallbackReady, isTrue);
    first.dispose();
  });

  testWidgets('failed preparation never blocks the normal app subtree',
      (tester) async {
    final preloader = KundiHomeAvatarLoadingFramePreloader(
      decodeFrame: (_) async => throw StateError('decode failed'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: KundiHomeAvatarLoadingFrameGate(
          enabled: true,
          loading: const SizedBox(key: Key('startup-surface')),
          preloader: preloader,
          builder: (context, frame) => SizedBox(
            key: const Key('normal-app-subtree'),
            child: Text('${frame == null}'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('startup-surface')), findsNothing);
    expect(find.byKey(const Key('normal-app-subtree')), findsOneWidget);
    expect(find.text('true'), findsOneWidget);
  });

  testWidgets('prepared Home is not built before both ui.Images resolve',
      (tester) async {
    final primaryDecoded = Completer<ui.Image>();
    final fallbackDecoded = Completer<ui.Image>();
    final preloader = KundiHomeAvatarLoadingFramePreloader(
      decodeFrame: (assetPath) =>
          assetPath == KundiHomeAvatarPlacement.loadingAssetPath
              ? primaryDecoded.future
              : fallbackDecoded.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: KundiHomeAvatarLoadingFrameGate(
          enabled: true,
          loading: const SizedBox(key: Key('startup-surface')),
          preloader: preloader,
          builder: (context, frame) => const SizedBox(
            key: Key('first-home-build'),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('startup-surface')), findsOneWidget);
    expect(find.byKey(const Key('first-home-build')), findsNothing);

    primaryDecoded.complete(await _testImage(Colors.blue));
    await tester.pump();
    expect(find.byKey(const Key('first-home-build')), findsNothing);

    fallbackDecoded.complete(await _testImage(Colors.purple));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('startup-surface')), findsNothing);
    expect(find.byKey(const Key('first-home-build')), findsOneWidget);
  });

  testWidgets('disabled rollout performs no realtime decode', (tester) async {
    var decodeCalls = 0;
    final preloader = KundiHomeAvatarLoadingFramePreloader(
      decodeFrame: (_) async {
        decodeCalls++;
        return _testImage(Colors.red);
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: KundiHomeAvatarLoadingFrameGate(
          enabled: false,
          loading: const SizedBox(key: Key('startup-surface')),
          preloader: preloader,
          builder: (context, frame) => Text(
            '${frame == null}',
            key: const Key('normal-app-subtree'),
          ),
        ),
      ),
    );

    expect(decodeCalls, 0);
    expect(find.byKey(const Key('normal-app-subtree')), findsOneWidget);
    expect(find.text('true'), findsOneWidget);
  });

  testWidgets('gate owns holder until its MainShell subtree is removed',
      (tester) async {
    final primary = await _testImage(Colors.blue);
    final fallback = await _testImage(Colors.purple);
    KundiHomeAvatarLoadingFrame? prepared;
    final preloader = KundiHomeAvatarLoadingFramePreloader(
      decodeFrame: (assetPath) async =>
          assetPath == KundiHomeAvatarPlacement.loadingAssetPath
              ? primary
              : fallback,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: KundiHomeAvatarLoadingFrameGate(
          enabled: true,
          loading: const SizedBox(),
          preloader: preloader,
          builder: (context, frame) {
            prepared = frame;
            return RawImage(image: frame!.loadingImage);
          },
        ),
      ),
    );
    await tester.pump();

    expect(prepared, isNotNull);
    expect(prepared!.isDisposed, isFalse);
    expect(find.byType(RawImage), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(prepared!.isDisposed, isTrue);
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
