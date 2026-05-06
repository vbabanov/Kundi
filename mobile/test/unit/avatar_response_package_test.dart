import 'package:flutter_test/flutter_test.dart';

import 'package:kundi_mobile/runtimes/avatar_runtime/contracts/avatar_response_package.dart';

void main() {
  test('avatar response package serializes', () {
    const response = AvatarResponsePackage(
      text: 'Hello',
      audioUrl: 'https://audio.example/test.mp3',
      audioStatus: AvatarAudioStatus.ready,
      visemes: <AvatarViseme>[
        AvatarViseme(offsetMs: 0, id: 'A', weight: 1.0),
      ],
      emotion: 'joy',
      gestureTags: <String>['explain'],
      pedagogyFlags: AvatarPedagogyFlags(
        needsScaffold: true,
        containsHint: true,
        containsStepPlan: true,
        safetyIntervention: false,
      ),
    );

    final json = response.toJson();
    expect(json['text'], 'Hello');
    expect(json['emotion'], 'joy');
    expect(json['audioStatus'], 'ready');
    expect((json['visemes'] as List<dynamic>).length, 1);
  });
}
