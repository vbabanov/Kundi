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
import '../../lessons/application/lessons_controller.dart';
import '../../lessons/presentation/lessons_page.dart';
import '../../profile/application/profile_controller.dart';
import '../../summary/application/summary_controller.dart';
import '../application/auth_controller.dart';

class MainShellPage extends ConsumerStatefulWidget {
  const MainShellPage({super.key});

  @override
  ConsumerState<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends ConsumerState<MainShellPage> {
  static const _initialPage = 1;
  late final PageController _pageController =
      PageController(initialPage: _initialPage);
  int _rootPageIndex = _initialPage;

  static const _rootPages = <Widget>[
    HomeworkPage(),
    LessonsPage(),
    GradesPage(),
  ];

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
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapMainScreen();
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _pageController.dispose();
    super.dispose();
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
          },
          children: _rootPages,
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
              height: 76,
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
                            _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                            );
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: selected ? 64 : 0,
                                height: selected ? 3 : 0,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF4FCB),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Icon(
                                _rootIcons[index],
                                size: selected ? 25 : 23,
                                color: color,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _rootLabels[index],
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontSize: selected ? 11.9 : 11.2,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: color,
                                    ),
                              ),
                              const SizedBox(height: 4),
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
