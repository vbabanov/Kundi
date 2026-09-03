import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_home_avatar_placement.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_native_avatar_controller.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_native_avatar_texture_view.dart';

void main() {
  testWidgets('flutter_texture uses Texture and never creates AndroidView', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final bridge = _FakeTextureBridge();
    KundiNativeAvatarController? controller;
    final availableIds = <int>[];
    final mountedIds = <int>[];

    await tester.pumpWidget(
      _app(
        size: const Size(160, 220),
        child: KundiNativeAvatarTextureView(
          bridge: bridge,
          onControllerCreated: (value) => controller = value,
          onTextureAvailable: availableIds.add,
          onTextureMounted: mountedIds.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(Texture), findsOneWidget);
    expect(find.byType(AndroidView), findsNothing);
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 42);
    expect(tester.getSize(find.byType(Texture)), const Size(160, 220));
    expect(controller, isNotNull);
    expect(availableIds, <int>[42]);
    expect(mountedIds, <int>[42]);
    expect(bridge.createCalls, 1);
    expect(
      bridge.lastConfiguration!.toCreateArguments()['cameraDistance'],
      KundiHomeAvatarPlacement.cameraDistance,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('rebuild and identical size do not recreate model session', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final bridge = _FakeTextureBridge();
    final key = GlobalKey();

    Widget candidate(Size size) => _app(
      size: size,
      child: KundiNativeAvatarTextureView(
        key: key,
        bridge: bridge,
        onControllerCreated: (_) {},
        onTextureAvailable: (_) {},
        onTextureMounted: (_) {},
      ),
    );

    await tester.pumpWidget(candidate(const Size(160, 220)));
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(candidate(const Size(160, 220)));
    await tester.pump();

    expect(bridge.createCalls, 1);
    expect(bridge.resizeCalls, 0);

    await tester.pumpWidget(candidate(const Size(180, 220)));
    await tester.pump();
    await tester.pump();

    expect(bridge.createCalls, 1);
    expect(bridge.resizeCalls, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _app({required Size size, required Widget child}) => MaterialApp(
  home: Center(
    child: SizedBox.fromSize(size: size, child: child),
  ),
);

final class _FakeTextureBridge implements KundiNativeAvatarTextureBridge {
  final StreamController<Object?> _events =
      StreamController<Object?>.broadcast();
  int createCalls = 0;
  int resizeCalls = 0;
  int disposeCalls = 0;
  KundiNativeAvatarTextureConfiguration? lastConfiguration;

  @override
  Future<int> create(
    KundiNativeAvatarTextureConfiguration configuration,
  ) async {
    createCalls++;
    lastConfiguration = configuration;
    return 42;
  }

  @override
  Future<void> resize(
    int textureId,
    KundiNativeAvatarTextureConfiguration configuration,
  ) async {
    resizeCalls++;
  }

  @override
  Stream<Object?> eventsFor(int textureId) => _events.stream;

  @override
  Future<Object?> send(int textureId, Map<String, Object> envelope) async =>
      const <String, Object>{'accepted': true};

  @override
  Future<void> disposeTexture(int textureId) async {
    disposeCalls++;
  }
}
