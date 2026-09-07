import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/theme/kundi_tokens.dart';
import '../../grades/application/grades_controller.dart';
import '../../grades/presentation/grades_page.dart';
import '../../assistant/assistant_feature.dart';
import '../../assistant/application/assistant_voice_locale_resolver.dart';
import '../../assistant/application/kundi_voice_assistant_coordinator.dart';
import '../../assistant/presentation/assistant_page.dart';
import '../../homework/application/homework_controller.dart';
import '../../homework/presentation/homework_page.dart';
import '../../kundi_behavior/application/kundi_behavior_controller.dart';
import '../../lessons/application/lessons_controller.dart';
import '../../lessons/presentation/lessons_page.dart';
import '../../profile/application/profile_controller.dart';
import '../../summary/application/summary_controller.dart';
import '../../../runtimes/kundi_native_avatar/kundi_home_avatar_loading_frame.dart';
import '../../../runtimes/kundi_native_avatar/kundi_native_avatar_feature.dart';
import '../../../runtimes/kundi_native_avatar/kundi_native_avatar_prewarm.dart';
import '../../../runtimes/kundi_system_speech/kundi_system_speech_controller.dart';
import '../../../runtimes/kundi_system_speech/kundi_system_speech_transport.dart';
import '../../../runtimes/kundi_system_speech/kundi_voice_qa_telemetry.dart';
import '../application/auth_controller.dart';

final class _VoiceGestureTransaction {
  const _VoiceGestureTransaction({
    required this.generation,
    required this.gestureId,
    required this.pointerSequenceId,
  });

  final int generation;
  final String gestureId;
  final String pointerSequenceId;
}

class MainShellPage extends ConsumerStatefulWidget {
  const MainShellPage({
    this.avatarLoadingFrame,
    super.key,
  });

  final KundiHomeAvatarLoadingFrame? avatarLoadingFrame;

  @override
  ConsumerState<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends ConsumerState<MainShellPage>
    with WidgetsBindingObserver {
  static const _initialPage = 1;
  late final PageController _pageController =
      PageController(initialPage: _initialPage);
  int _rootPageIndex = _initialPage;
  bool _homePageSettled = true;
  late final bool _behaviorCoreEnabled;
  late final bool _voiceInputEnabled;
  bool _avatarRuntimeReady = false;
  bool _avatarRuntimeResolved = false;
  bool _assistantRouteVisible = false;
  int _voiceGestureGeneration = 0;
  _VoiceGestureTransaction? _activeVoiceGesture;
  int? _tapSuppressionGeneration;
  String _activePointerSequenceId = '';
  String _activeGestureId = '';
  bool _voiceLocalePreparing = false;

  static const _rootLabels = <String>[
    'ДЗ',
    'Главная',
    'Оценки',
  ];

  static const _rootIcons = <IconData>[
    Icons.home_outlined,
    Icons.wb_sunny_outlined,
    Icons.bar_chart_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_handleRootPageScroll);
    _behaviorCoreEnabled = ref.read(kundiBehaviorCoreEnabledProvider);
    _voiceInputEnabled = ref.read(kundiAssistantEnabledProvider) &&
        ref.read(kundiVoiceInputEnabledProvider);
    if (_behaviorCoreEnabled || _voiceInputEnabled) {
      WidgetsBinding.instance.addObserver(this);
    }
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_behaviorCoreEnabled) {
        final behavior = ref.read(kundiBehaviorControllerProvider.notifier);
        behavior.appOpened();
        behavior.homeVisible();
      }
      if (KundiNativeAvatarFeature.enabled) {
        unawaited(_prewarmAvatar());
      }
      _bootstrapMainScreen();
    });
  }

  @override
  void dispose() {
    final gesture = _activeVoiceGesture;
    if (gesture != null) {
      _finishVoiceGesture(
        gesture.generation,
        reason: 'dispose',
        suppressTrailingTap: false,
      );
    }
    _pageController.removeListener(_handleRootPageScroll);
    if (_behaviorCoreEnabled || _voiceInputEnabled) {
      WidgetsBinding.instance.removeObserver(this);
    }
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _pageController.dispose();
    super.dispose();
  }

  void _handleRootPageScroll() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page;
    if (page == null) return;
    final settled = (page - _initialPage).abs() < 0.001;
    if (_homePageSettled == settled) return;
    setState(() => _homePageSettled = settled);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_voiceInputEnabled && state != AppLifecycleState.resumed) {
      final gesture = _activeVoiceGesture;
      if (gesture != null) {
        _finishVoiceGesture(gesture.generation, reason: 'app_lifecycle_cancel');
      }
      unawaited(
        ref.read(kundiVoiceAssistantCoordinatorProvider.notifier).cancel(),
      );
    }
    if (_behaviorCoreEnabled &&
        state == AppLifecycleState.resumed &&
        _rootPageIndex == _initialPage) {
      ref.read(kundiBehaviorControllerProvider.notifier).homeVisible();
    }
  }

  Future<void> _bootstrapMainScreen() async {
    _logMainStage(stage: 'main_screen_init_start', outcome: 'started');
    try {
      final baselineSession = await ref
          .read(authControllerProvider.notifier)
          .ensureSessionBaseline();
      if (baselineSession == null) {
        final reason = await _resolveNoSessionReason();
        _logMainStage(
          stage: 'main_screen_auth_baseline_result',
          outcome: 'no_session',
          details: {'reason': reason},
        );
        return;
      }
      _logMainStage(
        stage: 'main_screen_auth_baseline_result',
        outcome: 'success',
      );
      await Future.wait([
        ref.read(lessonsControllerProvider.notifier).refreshFromCache(),
        ref.read(homeworkControllerProvider.notifier).refreshFromCache(),
        ref.read(gradesControllerProvider.notifier).refreshFromCache(),
        ref.read(profileControllerProvider.notifier).refreshFromCache(),
        ref.read(summaryControllerProvider.notifier).refreshFromCache(),
      ]);
      _logMainStage(stage: 'main_screen_init_result', outcome: 'success');
    } catch (error) {
      _logMainStage(
        stage: 'final_post_login_error',
        outcome: 'main_screen_init_failed',
        details: {'error': _sanitizeError(error.toString())},
      );
    }
  }

  Future<void> _prewarmAvatar() async {
    try {
      final result = await KundiNativeAvatarPrewarm.run();
      if (!mounted) return;
      setState(() {
        _avatarRuntimeReady = KundiNativeAvatarPrewarm.isRuntimeReady(result);
        _avatarRuntimeResolved = true;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _avatarRuntimeReady = false;
        _avatarRuntimeResolved = true;
      });
    }
  }

  Future<String> _resolveNoSessionReason() async {
    final authState = ref.read(authControllerProvider);
    if (authState.isLoading) {
      return 'not_persisted_yet';
    }

    final stored = await ref.read(secureStorageProvider).loadAuthSession();
    final studentId = (stored['student_id'] ?? '').trim();
    final accessToken = (stored['access_token'] ?? '').trim();
    final expiresAtRaw = (stored['expires_at'] ?? '').trim();

    if (studentId.isEmpty || accessToken.isEmpty || expiresAtRaw.isEmpty) {
      return 'no_session_store_empty';
    }

    final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
    if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) {
      return 'token_expired';
    }

    return 'unknown';
  }

  void _logMainStage({
    required String stage,
    required String outcome,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) {
    debugPrint(
      '[KUNDI_POST_LOGIN] ${jsonEncode({
            'stage': stage,
            'outcome': outcome,
            ...details,
          })}',
    );
  }

  String _sanitizeError(String message) {
    final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 180) {
      return normalized;
    }
    return '${normalized.substring(0, 180)}...';
  }

  void _showRootPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openAssistant() async {
    if (_voiceInputEnabled) {
      final gesture = _activeVoiceGesture;
      if (gesture != null) {
        _finishVoiceGesture(gesture.generation, reason: 'navigation_cancel');
      }
      final speech = ref.read(kundiVoiceAssistantCoordinatorProvider);
      if (speech.status == KundiSpeechRecognitionStatus.listening ||
          speech.status == KundiSpeechRecognitionStatus.processing) {
        await ref
            .read(kundiVoiceAssistantCoordinatorProvider.notifier)
            .cancel();
      }
    }
    if (!mounted) return;
    if (_behaviorCoreEnabled) {
      ref.read(kundiBehaviorControllerProvider.notifier).dismiss();
    }
    setState(() => _assistantRouteVisible = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AssistantPage()),
      );
    } finally {
      if (mounted) {
        setState(() => _assistantRouteVisible = false);
      }
    }
  }

  void _voicePointerDown() {
    _activePointerSequenceId = KundiVoiceQaTelemetry.nextId('pointer');
    _activeGestureId = '';
    KundiVoiceQaTelemetry.event(
      'pointerDown',
      pointerSequenceId: _activePointerSequenceId,
    );
  }

  void _voicePointerUp() {
    KundiVoiceQaTelemetry.event(
      'pointerUp',
      gestureId: _activeGestureId.isEmpty ? null : _activeGestureId,
      pointerSequenceId: _activePointerSequenceId,
    );
  }

  void _voicePointerCancel() {
    final gesture = _activeVoiceGesture;
    KundiVoiceQaTelemetry.event(
      'gestureCancelled',
      gestureId: gesture?.gestureId,
      pointerSequenceId: _activePointerSequenceId,
      outcome: 'pointer_cancel',
    );
    if (gesture != null) {
      _finishVoiceGesture(
        gesture.generation,
        reason: 'pointer_cancel',
        suppressTrailingTap: false,
      );
      unawaited(
        ref.read(kundiVoiceAssistantCoordinatorProvider.notifier).cancel(),
      );
    }
  }

  Future<void> _startVoiceHold() async {
    final previous = _activeVoiceGesture;
    if (previous != null) {
      _finishVoiceGesture(previous.generation, reason: 'superseded');
      unawaited(
        ref.read(kundiVoiceAssistantCoordinatorProvider.notifier).cancel(),
      );
    }
    final gesture = _VoiceGestureTransaction(
      generation: ++_voiceGestureGeneration,
      gestureId: KundiVoiceQaTelemetry.nextId('gesture'),
      pointerSequenceId: _activePointerSequenceId.isEmpty
          ? KundiVoiceQaTelemetry.nextId('pointer-fallback')
          : _activePointerSequenceId,
    );
    _activeVoiceGesture = gesture;
    _activeGestureId = gesture.gestureId;
    _activePointerSequenceId = gesture.pointerSequenceId;
    KundiVoiceQaTelemetry.event(
      'voiceTapGuardSet',
      gestureId: gesture.gestureId,
      pointerSequenceId: gesture.pointerSequenceId,
      gestureGeneration: gesture.generation,
    );
    KundiVoiceQaTelemetry.event(
      'longPressAccepted',
      gestureId: gesture.gestureId,
      pointerSequenceId: gesture.pointerSequenceId,
      gestureGeneration: gesture.generation,
    );
    HapticFeedback.mediumImpact();
    if (mounted) setState(() => _voiceLocalePreparing = true);
    final resolution =
        await ref.read(assistantVoiceLocaleResolverProvider).resolve();
    if (!mounted || !_isActiveVoiceGesture(gesture.generation)) return;
    setState(() => _voiceLocalePreparing = false);
    KundiVoiceQaTelemetry.event(
      'voiceLocaleResolved',
      gestureId: gesture.gestureId,
      pointerSequenceId: gesture.pointerSequenceId,
      gestureGeneration: gesture.generation,
      sessionLocale: resolution.locale,
      outcome: resolution.source.name,
    );
    final outcome = await ref
        .read(kundiVoiceAssistantCoordinatorProvider.notifier)
        .beginHold(
          resolution.locale,
          gestureId: gesture.gestureId,
          pointerSequenceId: gesture.pointerSequenceId,
        );
    if (!mounted || !_isActiveVoiceGesture(gesture.generation)) return;
    switch (outcome) {
      case KundiVoiceStartOutcome.permissionExplanationRequired:
        _finishVoiceGesture(
          gesture.generation,
          reason: 'permission_required',
          suppressTrailingTap: false,
        );
        await _showMicrophoneExplanation(gesture.generation);
      case KundiVoiceStartOutcome.permissionPermanentlyDenied:
        _finishVoiceGesture(
          gesture.generation,
          reason: 'permission_permanently_denied',
          suppressTrailingTap: false,
        );
        await _showMicrophoneSettings(gesture.generation);
      case KundiVoiceStartOutcome.unavailable:
        _finishVoiceGesture(
          gesture.generation,
          reason: 'recognizer_unavailable',
          suppressTrailingTap: false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Системное распознавание речи недоступно.'),
          ),
        );
      case KundiVoiceStartOutcome.listening:
        break;
      case KundiVoiceStartOutcome.busy:
        _finishVoiceGesture(
          gesture.generation,
          reason: 'recognizer_busy',
          suppressTrailingTap: false,
        );
        break;
    }
  }

  bool _hasNewerVoiceGesture(int generation) =>
      generation != _voiceGestureGeneration;

  bool _isActiveVoiceGesture(int generation) =>
      _activeVoiceGesture?.generation == generation;

  bool _finishVoiceGesture(
    int generation, {
    required String reason,
    bool suppressTrailingTap = true,
  }) {
    final gesture = _activeVoiceGesture;
    if (gesture == null || gesture.generation != generation) return false;

    _activeVoiceGesture = null;
    if (_voiceLocalePreparing) {
      _voiceLocalePreparing = false;
      if (mounted && reason != 'dispose') setState(() {});
    }
    KundiVoiceQaTelemetry.event(
      'voiceGestureFinalized',
      gestureId: gesture.gestureId,
      pointerSequenceId: gesture.pointerSequenceId,
      gestureGeneration: generation,
      reason: reason,
    );
    if (!suppressTrailingTap) {
      _clearTapSuppression(generation, reason: reason);
      return true;
    }

    _tapSuppressionGeneration = generation;
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tapSuppressionGeneration == generation) {
        _clearTapSuppression(generation, reason: 'frame_complete');
      }
    });
    return true;
  }

  void _clearTapSuppression(int generation, {required String reason}) {
    if (_tapSuppressionGeneration == generation) {
      _tapSuppressionGeneration = null;
    }
    KundiVoiceQaTelemetry.event(
      'voiceTapGuardReset',
      gestureGeneration: generation,
      reason: reason,
    );
  }

  void _handleAssistantTap() {
    final active = _activeVoiceGesture;
    if (active != null) {
      KundiVoiceQaTelemetry.event(
        'voiceTapSuppressed',
        gestureId: active.gestureId,
        pointerSequenceId: active.pointerSequenceId,
        gestureGeneration: active.generation,
        reason: 'active_voice_gesture',
      );
      return;
    }
    final suppressionGeneration = _tapSuppressionGeneration;
    if (suppressionGeneration != null) {
      KundiVoiceQaTelemetry.event(
        'voiceTapSuppressed',
        gestureGeneration: suppressionGeneration,
        reason: 'trailing_tap',
      );
      _clearTapSuppression(suppressionGeneration, reason: 'tap_suppressed');
      return;
    }
    unawaited(_openAssistant());
  }

  Future<void> _showMicrophoneExplanation(int generation) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Разрешить микрофон?'),
        content: const Text(
          'Микрофон работает только во время удержания Kundi. '
          'Приложение не записывает и не хранит аудио. Системная служба '
          'устройства может обрабатывать речь локально или через своего '
          'поставщика. Распознанный текст сохраняется в истории диалога.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Не сейчас'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || _hasNewerVoiceGesture(generation)) {
      _finishVoiceGesture(
        generation,
        reason: 'permission_explanation_dismissed',
      );
      return;
    }
    try {
      final permission = await ref
          .read(kundiVoiceAssistantCoordinatorProvider.notifier)
          .requestPermission();
      if (!mounted || _hasNewerVoiceGesture(generation)) return;
      if (permission == KundiSpeechPermission.granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Теперь удерживай Kundi и говори')),
        );
      } else if (permission == KundiSpeechPermission.permanentlyDenied) {
        await _showMicrophoneSettings(generation);
      }
    } finally {
      _finishVoiceGesture(generation, reason: 'permission_request_complete');
    }
  }

  Future<void> _showMicrophoneSettings(int generation) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Микрофон выключен'),
        content: const Text(
          'Разрешение можно включить в настройках приложения. '
          'Текстовый помощник продолжает работать без микрофона.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Закрыть'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
    try {
      if (open == true && mounted && !_hasNewerVoiceGesture(generation)) {
        await ref
            .read(kundiVoiceAssistantCoordinatorProvider.notifier)
            .openAppSettings();
      }
    } finally {
      _finishVoiceGesture(generation, reason: 'permission_settings_closed');
    }
  }

  void _endVoiceHold() {
    final gesture = _activeVoiceGesture;
    if (gesture == null) return;
    KundiVoiceQaTelemetry.event(
      'longPressReleased',
      gestureId: gesture.gestureId,
      pointerSequenceId: gesture.pointerSequenceId,
      gestureGeneration: gesture.generation,
    );
    unawaited(
      ref.read(kundiVoiceAssistantCoordinatorProvider.notifier).endHold(),
    );
    _finishVoiceGesture(gesture.generation, reason: 'long_press_end');
  }

  String _voiceStatus(KundiSpeechRecognitionState speech) {
    if (_voiceLocalePreparing) return 'Подготавливаю Kundi…';
    return switch (speech.status) {
      KundiSpeechRecognitionStatus.listening => speech.partialText.isEmpty
          ? 'Я слушаю… Говори, пока удерживаешь Kundi'
          : speech.partialText,
      KundiSpeechRecognitionStatus.processing => 'Обрабатываю речь…',
      KundiSpeechRecognitionStatus.recognized ||
      KundiSpeechRecognitionStatus.sending =>
        'Думаю…',
      KundiSpeechRecognitionStatus.error =>
        speech.errorCode == 'no_speech' || speech.errorCode == 'no_match'
            ? 'Не расслышала. Попробуй ещё раз.'
            : 'Не удалось распознать речь.',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: scheme.kundiBackground,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );
    final assistantEnabled = ref.watch(kundiAssistantEnabledProvider);
    final voiceEnabled =
        assistantEnabled && ref.watch(kundiVoiceInputEnabledProvider);
    final speech = voiceEnabled
        ? ref.watch(kundiVoiceAssistantCoordinatorProvider)
        : const KundiSpeechRecognitionState();

    final rootPages = <Widget>[
      const HomeworkPage(),
      _MainShellKeepAlivePage(
        child: LessonsPage(
          onHomeworkTap: () => _showRootPage(0),
          onGradesTap: () => _showRootPage(2),
          assistantEnabled: assistantEnabled,
          onAssistantTap: assistantEnabled ? _handleAssistantTap : null,
          onAssistantPointerDown:
              voiceEnabled ? (_) => _voicePointerDown() : null,
          onAssistantPointerUp: voiceEnabled ? (_) => _voicePointerUp() : null,
          onAssistantPointerCancel:
              voiceEnabled ? (_) => _voicePointerCancel() : null,
          onAssistantLongPressStart:
              voiceEnabled ? (_) => unawaited(_startVoiceHold()) : null,
          onAssistantLongPressEnd: voiceEnabled ? (_) => _endVoiceHold() : null,
          onAssistantLongPressCancel: voiceEnabled
              ? () {
                  final gesture = _activeVoiceGesture;
                  KundiVoiceQaTelemetry.event(
                    'gestureCancelled',
                    gestureId: gesture?.gestureId,
                    pointerSequenceId: _activePointerSequenceId,
                    outcome: 'long_press_cancel',
                  );
                  if (gesture != null) {
                    _finishVoiceGesture(
                      gesture.generation,
                      reason: 'long_press_cancel',
                      suppressTrailingTap: false,
                    );
                    unawaited(ref
                        .read(kundiVoiceAssistantCoordinatorProvider.notifier)
                        .cancel());
                  }
                }
              : null,
          voiceStatusText: voiceEnabled ? _voiceStatus(speech) : '',
          voiceListening: voiceEnabled &&
              speech.status == KundiSpeechRecognitionStatus.listening,
          realtimeAvatarEnabled:
              KundiNativeAvatarFeature.enabled && _avatarRuntimeReady,
          realtimeAvatarPreparing:
              KundiNativeAvatarFeature.enabled && !_avatarRuntimeResolved,
          realtimeAvatarLoadingFrame: widget.avatarLoadingFrame,
          isHomeVisible: _rootPageIndex == _initialPage &&
              _homePageSettled &&
              !_assistantRouteVisible,
        ),
      ),
      const GradesPage(),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          onPageChanged: (index) {
            if (_rootPageIndex == index) {
              return;
            }
            setState(() => _rootPageIndex = index);
            if (_voiceInputEnabled && index != _initialPage) {
              unawaited(
                ref
                    .read(kundiVoiceAssistantCoordinatorProvider.notifier)
                    .cancel(),
              );
            }
            if (_behaviorCoreEnabled && index == _initialPage) {
              ref.read(kundiBehaviorControllerProvider.notifier).homeVisible();
            }
          },
          children: rootPages,
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0B0921), Color(0xFF171033)],
            ),
            border: Border(
              top: BorderSide(color: Color(0xB334275F), width: 1),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 42,
              child: Row(
                children: List.generate(
                  _rootLabels.length,
                  (index) {
                    final selected = index == _rootPageIndex;
                    final color = selected
                        ? const Color(0xFFF74FC8)
                        : const Color(0xD99A8FC8);
                    return Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            _showRootPage(index);
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: selected ? 54 : 0,
                                height: selected ? 2 : 0,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF4FCB),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Icon(
                                _rootIcons[index],
                                size: selected ? 20 : 18,
                                color: color,
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _rootLabels[index],
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontSize: selected ? 10.0 : 9.5,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: color,
                                    ),
                              ),
                              const SizedBox(height: 1),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MainShellKeepAlivePage extends StatefulWidget {
  const _MainShellKeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_MainShellKeepAlivePage> createState() =>
      _MainShellKeepAlivePageState();
}

class _MainShellKeepAlivePageState extends State<_MainShellKeepAlivePage>
    with AutomaticKeepAliveClientMixin<_MainShellKeepAlivePage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
