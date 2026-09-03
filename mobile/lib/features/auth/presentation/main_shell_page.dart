import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/theme/kundi_tokens.dart';
import '../../grades/application/grades_controller.dart';
import '../../grades/presentation/grades_page.dart';
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
import '../application/auth_controller.dart';

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
  bool _avatarRuntimeReady = false;
  bool _avatarRuntimeResolved = false;

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
    if (_behaviorCoreEnabled) {
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
    _pageController.removeListener(_handleRootPageScroll);
    if (_behaviorCoreEnabled) {
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

    final rootPages = <Widget>[
      const HomeworkPage(),
      _MainShellKeepAlivePage(
        child: LessonsPage(
          onHomeworkTap: () => _showRootPage(0),
          onGradesTap: () => _showRootPage(2),
          realtimeAvatarEnabled:
              KundiNativeAvatarFeature.enabled && _avatarRuntimeReady,
          realtimeAvatarPreparing:
              KundiNativeAvatarFeature.enabled && !_avatarRuntimeResolved,
          realtimeAvatarLoadingFrame: widget.avatarLoadingFrame,
          isHomeVisible: _rootPageIndex == _initialPage && _homePageSettled,
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
