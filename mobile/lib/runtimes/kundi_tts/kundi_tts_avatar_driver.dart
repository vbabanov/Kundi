import '../../features/assistant/application/kundi_tts_coordinator.dart';
import '../kundi_native_avatar/kundi_avatar_animation_policy.dart';
import '../kundi_native_avatar/kundi_native_avatar_controller.dart';
import '../kundi_native_avatar/kundi_native_avatar_protocol.dart';

/// Mouth and body have independent commands. Async command tails are invalidated
/// on every state transition, including interruption and controller replacement.
final class KundiTtsAvatarDriver {
  KundiNativeAvatarController? _controller;
  KundiTtsState? _previous;
  int _generation = 0;
  void invalidate() {
    _generation++;
    _previous = null;
    _controller = null;
  }

  Future<void> apply(
      KundiNativeAvatarController controller, KundiTtsState next) async {
    final before = identical(_controller, controller) ? _previous : null;
    _controller = controller;
    _previous = next;
    final bodyChanged =
        before?.status != next.status || before?.messageId != next.messageId;
    // A mouth event must not cancel an in-flight Waiting -> Talking command.
    if (bodyChanged) _generation++;
    final generation = _generation;
    bool current() => generation == _generation;
    try {
      if (bodyChanged) {
        await controller.resetFace();
        if (!current()) return;
        if (next.status == KundiTtsStatus.synthesizing) {
          await controller.playWaiting();
        } else if (next.status == KundiTtsStatus.speaking) {
          await controller.playTalking(
              KundiAvatarAnimationPolicy.talkingVariant(next.messageId));
        } else {
          await controller.setViseme(KundiNativeAvatarViseme.neutral);
          if (!current()) return;
          await controller.settleRestPose();
        }
      }
      final latest = _previous;
      if (current() && latest?.status == KundiTtsStatus.speaking) {
        final mouth = KundiNativeAvatarViseme.values
            .firstWhere((v) => v.wireName == latest!.viseme);
        await controller.setViseme(mouth);
      }
    } catch (_) {
      /* Avatar fallback must not turn successful audio into failure. */
    }
  }
}
