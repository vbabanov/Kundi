import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../runtimes/kundi_system_speech/terminal_request_cache.dart';
import '../../../runtimes/kundi_tts/kundi_tts_transport.dart';
import '../../../runtimes/kundi_native_avatar/kundi_native_avatar_protocol.dart';
import '../../../shared/providers/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../assistant_feature.dart';
import '../domain/assistant_entity.dart';

const kundiTtsEnabledByDefault =
    bool.fromEnvironment('ENABLE_KUNDI_TTS', defaultValue: false);
final kundiTtsEnabledProvider = Provider<bool>((ref) =>
    kundiTtsEnabledByDefault &&
    ref.watch(kundiAssistantEnabledProvider) &&
    ref.watch(kundiVoiceInputEnabledProvider));
final kundiTtsTransportProvider =
    Provider<KundiTtsTransport>((ref) => MethodChannelKundiTtsTransport());

final kundiTtsCoordinatorProvider =
    StateNotifierProvider<KundiTtsCoordinator, KundiTtsState>((ref) {
  final token = ref.watch(
      authControllerProvider.select((value) => value.valueOrNull?.accessToken));
  return KundiTtsCoordinator(
    enabled: ref.watch(kundiTtsEnabledProvider),
    transport: ref.watch(kundiTtsTransportProvider),
    authorize: (message) async {
      if (token == null || token.isEmpty) {
        throw StateError('Speech unavailable');
      }
      try {
        final response = await ref.read(apiClientProvider).post(
              '/v1/assistant/sessions/${Uri.encodeComponent(message.sessionId)}/messages/${Uri.encodeComponent(message.id)}/speech-authorization',
              data: const <String, Object>{},
              options: Options(
                  headers: {'Authorization': 'Bearer $token'},
                  sendTimeout: const Duration(seconds: 8),
                  receiveTimeout: const Duration(seconds: 8)),
            );
        final root = Map<String, dynamic>.from(response.data as Map);
        return Map<String, dynamic>.from((root['data'] ?? root) as Map);
      } catch (_) {
        throw StateError('Speech unavailable');
      }
    },
  );
});

enum KundiTtsStatus { idle, synthesizing, speaking, error }

final class KundiTtsState {
  const KundiTtsState(
      {this.status = KundiTtsStatus.idle,
      this.messageId = '',
      this.viseme = 'Neutral',
      this.expression = const KundiFacialExpression.neutral()});
  final KundiTtsStatus status;
  final String messageId;
  final String viseme;
  final KundiFacialExpression expression;
  bool get active =>
      status == KundiTtsStatus.synthesizing ||
      status == KundiTtsStatus.speaking;
  String get errorMessage =>
      status == KundiTtsStatus.error ? 'Не удалось озвучить ответ' : '';
}

/// Only the foreground send completion calls speakResponse. History has no hook.
class KundiTtsCoordinator extends StateNotifier<KundiTtsState>
    with WidgetsBindingObserver {
  KundiTtsCoordinator(
      {required this.enabled,
      required KundiTtsTransport transport,
      required Future<Map<String, dynamic>> Function(AssistantMessageEntity)
          authorize})
      : _transport = transport,
        _authorize = authorize,
        super(const KundiTtsState()) {
    if (enabled) {
      _subscription =
          _transport.events.listen(_event, onError: (_) => _fail(_generation));
      WidgetsBinding.instance.addObserver(this);
      _foreground = WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    }
  }
  final bool enabled;
  final KundiTtsTransport _transport;
  final Future<Map<String, dynamic>> Function(AssistantMessageEntity)
      _authorize;
  StreamSubscription<KundiTtsEvent>? _subscription;
  final _terminal = TerminalRequestCache<bool>();
  static int _nextGeneration = 0;
  int _generation = 0;
  int _epoch = 0;
  bool _disposed = false;
  bool _foreground = true;
  String? _activeMessage;
  int get epoch => _epoch;

  Future<void> speakResponse(AssistantMessageResult result,
      {required int expectedEpoch}) async {
    if (!enabled ||
        _disposed ||
        !_foreground ||
        expectedEpoch != _epoch ||
        result.replayed ||
        result.userMessage.inputMode != 'voice' ||
        result.assistantMessage.role != 'assistant' ||
        result.assistantMessage.sessionId != result.userMessage.sessionId) {
      return;
    }
    final message = result.assistantMessage;
    if (message.id.isEmpty ||
        message.content.trim().isEmpty ||
        _activeMessage != null ||
        _terminal.contains(message.id)) {
      return;
    }
    _activeMessage = message.id;
    final generation = _generation = ++_nextGeneration;
    final expression = KundiFacialExpression.fromApi(
      emotion: result.emotion,
      intensity: result.emotionIntensity,
    );
    state = KundiTtsState(
        status: KundiTtsStatus.synthesizing,
        messageId: message.id,
        expression: expression);
    try {
      final auth =
          await _authorize(message).timeout(const Duration(seconds: 10));
      if (!_current(generation)) return;
      final expiry = DateTime.tryParse((auth['expires_at'] ?? '').toString());
      if (auth['message_id'] != message.id ||
          expiry == null ||
          !expiry.isAfter(DateTime.now().add(const Duration(minutes: 1))) ||
          auth['audio_format'] != 'raw-24khz-16bit-mono-pcm' ||
          auth['sample_rate_hz'] != 24000 ||
          auth['channels'] != 1 ||
          auth['bits_per_sample'] != 16) {
        throw StateError('Speech unavailable');
      }
      final accepted = await _transport.speak(generation, message.content, {
        ...auth,
        'expires_at_ms': expiry.millisecondsSinceEpoch,
      });
      if (!accepted) _fail(generation);
    } catch (_) {
      _fail(generation);
    }
  }

  bool _current(int generation) =>
      !_disposed &&
      _foreground &&
      _activeMessage != null &&
      generation == _generation;
  void _event(KundiTtsEvent event) {
    if (!_current(event.generation)) return;
    switch (event.type) {
      case KundiTtsEventType.synthesisStarted:
      case KundiTtsEventType.synthesisReady:
        break;
      case KundiTtsEventType.playbackStarted:
        state = KundiTtsState(
            status: KundiTtsStatus.speaking,
            messageId: _activeMessage!,
            expression: state.expression);
      case KundiTtsEventType.visemeDue:
        if (state.status == KundiTtsStatus.speaking) {
          state = KundiTtsState(
              status: state.status,
              messageId: _activeMessage!,
              viseme: event.viseme,
              expression: state.expression);
        }
      case KundiTtsEventType.playbackCompleted:
      case KundiTtsEventType.playbackCancelled:
        _finish();
        state = const KundiTtsState();
      case KundiTtsEventType.speechError:
        _fail(event.generation);
    }
  }

  void _finish() {
    final id = _activeMessage;
    if (id != null) _terminal.add(id, true);
    _activeMessage = null;
  }

  void _fail(int generation) {
    if (!_current(generation)) return;
    _finish();
    state = const KundiTtsState(status: KundiTtsStatus.error);
    unawaited(_transport.cancel().catchError((Object _) {}));
  }

  Future<void> cancel() async {
    if (_disposed || !enabled) return;
    _epoch++;
    _generation = ++_nextGeneration;
    _finish();
    state = const KundiTtsState();
    try {
      await _transport.cancel();
    } catch (_) {/* Local cancellation still wins. */}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(cancel());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _activeMessage = null;
    _terminal.clear();
    if (enabled) {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(_subscription?.cancel());
      // Host lifetime belongs to Activity, which permits a fresh auth scope to attach.
      unawaited(_transport.cancel().catchError((Object _) {}));
    }
    super.dispose();
  }
}
