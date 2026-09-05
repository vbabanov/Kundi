import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_avatar_animation_policy.dart';

void main() {
  test('neutral and unknown cues map to Standing', () {
    expect(
      KundiAvatarAnimationPolicy.resolve(
        cueName: 'neutral',
        identity: 'home:neutral',
      ).target,
      KundiAvatarAnimationTarget.standing,
    );
    expect(
      KundiAvatarAnimationPolicy.resolve(
        cueName: 'unknown',
        identity: 'home:unknown',
      ).target,
      KundiAvatarAnimationTarget.standing,
    );
  });

  test('listening uses Idle and thinking uses Waiting', () {
    expect(
      KundiAvatarAnimationPolicy.resolve(
        cueName: 'listen',
        identity: 'listen:1',
      ).target,
      KundiAvatarAnimationTarget.idle,
    );
    expect(
      KundiAvatarAnimationPolicy.resolve(
        cueName: 'think',
        identity: 'think:1',
      ).target,
      KundiAvatarAnimationTarget.waiting,
    );
  });

  test('speaking selects a deterministic Talking variant', () {
    final first = KundiAvatarAnimationPolicy.resolve(
      cueName: 'speak',
      identity: 'message:42',
    );
    final second = KundiAvatarAnimationPolicy.resolve(
      cueName: 'speak',
      identity: 'message:42',
    );

    expect(first.target, KundiAvatarAnimationTarget.talking);
    expect(
      KundiAvatarAnimationPolicy.frontalTalkingVariants,
      const <int>{2},
    );
    expect(first.talkingVariant, 2);
    expect(second.talkingVariant, first.talkingVariant);
  });

  test('side-facing Talking clips are excluded from Home speech', () {
    for (final identity in <String>['a', 'message:42', 'different-message']) {
      expect(KundiAvatarAnimationPolicy.talkingVariant(identity), 2);
      expect(
        KundiAvatarAnimationPolicy.frontalTalkingVariants,
        isNot(contains(1)),
      );
      expect(
        KundiAvatarAnimationPolicy.frontalTalkingVariants,
        isNot(contains(3)),
      );
    }
  });

  test('celebration uses Dansing', () {
    expect(
      KundiAvatarAnimationPolicy.resolve(
        cueName: 'celebrate',
        identity: 'achievement:1',
      ).target,
      KundiAvatarAnimationTarget.dansing,
    );
  });

  test('long wait allows one Dansing action and cancellation is immediate', () {
    final policy = KundiAvatarLongWaitPolicy(
      entertainmentThreshold: const Duration(seconds: 6),
    );

    expect(
      policy.actionFor(const Duration(seconds: 5)),
      KundiAvatarLongWaitAction.waiting,
    );
    expect(
      policy.actionFor(const Duration(seconds: 6)),
      KundiAvatarLongWaitAction.dansing,
    );
    expect(
      policy.actionFor(const Duration(seconds: 12)),
      KundiAvatarLongWaitAction.waiting,
    );

    policy.cancel();
    expect(
      policy.actionFor(const Duration(seconds: 13)),
      KundiAvatarLongWaitAction.standing,
    );
  });
}
