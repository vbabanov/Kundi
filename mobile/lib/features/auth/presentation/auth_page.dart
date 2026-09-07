import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/kundi_tokens.dart';
import '../application/auth_controller.dart';
import '../domain/auth_session.dart';

class AuthPage extends ConsumerWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final isCompact = width < 390;
          final logoScale = isCompact ? 0.92 : 1.0;
          final mascotWidth = math.min(width * 0.94, 446.0);
          final bubbleWidth = math.min(width * 0.34, 148.0);
          final cardWidth = math.min(width - 28, 430.0);
          final safeTop = MediaQuery.paddingOf(context).top;

          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  KundiPalette.deepNavy,
                  KundiPalette.deepIndigo,
                  KundiPalette.glassPurple,
                ],
              ),
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF090C27),
                            Color(0xFF120F39),
                            Color(0xFF080B24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0.18, 0.10),
                          radius: 0.82,
                          colors: [
                            Color(0x7C5C37F4),
                            Color(0x2A25146C),
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.26, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(child: _BackgroundOrbitRings()),
                const Positioned.fill(child: _SkyAccentLayer()),
                Positioned(
                  top: math.max(34, safeTop + 10),
                  left: 0,
                  right: 0,
                  child: _LogoBlock(scale: logoScale),
                ),
                Positioned(
                  top: isCompact ? 198 : 206,
                  left: isCompact ? 18 : 24,
                  child: _SpeechBubble(
                    width: bubbleWidth,
                    heightFactor: 0.67,
                  ),
                ),
                Positioned(
                  top: isCompact ? 138 : 126,
                  right: isCompact ? -64 : -52,
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/images/load_mascot.webp',
                      width: mascotWidth,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  left: (width - cardWidth) / 2,
                  top: isCompact ? height * 0.49 : height * 0.50,
                  width: cardWidth,
                  child: _AuthSelectionCard(
                    isLoading: authState.isLoading,
                    onSelectSource: (source) =>
                        _showSourceLoginSheet(context, source),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSourceLoginSheet(BuildContext context, String source) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SourceLoginSheet(source: source),
    );
  }
}

class _SourceLoginSheet extends ConsumerStatefulWidget {
  const _SourceLoginSheet({required this.source});

  final String source;

  @override
  ConsumerState<_SourceLoginSheet> createState() => _SourceLoginSheetState();
}

class _SourceLoginSheetState extends ConsumerState<_SourceLoginSheet> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  late final ProviderSubscription<AsyncValue<AuthSession?>> _authSubscription;
  bool _loginPending = false;
  bool _completionHandled = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _authSubscription = ref.listenManual(authControllerProvider, _handleAuth);
    _prefillSavedCredentials();
  }

  Future<void> _prefillSavedCredentials() async {
    try {
      final saved = await ref
          .read(authControllerProvider.notifier)
          .loadSavedCredentials();
      if (!mounted ||
          _completionHandled ||
          ModalRoute.of(context)?.isActive != true) {
        return;
      }
      // A delayed storage read must not replace input already entered by hand.
      if (_loginController.text.isEmpty) {
        _loginController.text = (saved['login'] ?? '').trim();
      }
      if (_passwordController.text.isEmpty) {
        _passwordController.text = (saved['password'] ?? '').trim();
      }
    } on Exception {
      // Saved credentials are optional; manual login remains available.
      if (mounted) {
        _logPostLoginStage(
            stage: 'saved_credentials_prefill', outcome: 'unavailable');
      }
    }
  }

  @override
  void dispose() {
    _authSubscription.close();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleAuth(
      AsyncValue<AuthSession?>? previous, AsyncValue<AuthSession?> next) {
    if (!mounted || _completionHandled || next.isLoading) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (next.hasError) {
      if (!_loginPending) return;
      setState(() {
        _loginPending = false;
        _errorMessage = 'Не удалось войти. Попробуйте ещё раз.';
      });
      _logPostLoginStage(stage: 'final_post_login_error', outcome: 'ui_error');
      return;
    }
    if (next.valueOrNull == null) return;
    _completionHandled = true;
    _loginPending = false;
    _logPostLoginStage(
      stage: 'login_success_ui',
      outcome: 'success',
      details: {
        'source': widget.source,
        'login': _redactLogin(_loginController.text.trim()),
      },
    );
    final navigator = route.navigator!;
    final messenger = ScaffoldMessenger.of(context);
    // Close this sheet only, even if another route was placed above it.
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
    messenger.showSnackBar(const SnackBar(content: Text('Login successful')));
    _logPostLoginStage(
      stage: 'route_transition_result',
      outcome: 'handled_by_root_auth_state',
      details: {'target': 'app_home_router'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = widget.source;
    final isLoading =
        _loginPending || ref.watch(authControllerProvider).isLoading;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset + 14),
      child: _SheetGlass(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _ProviderMark(source: source, compact: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Вход через ${_sourceLabel(source)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Логин и пароль от электронного дневника',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.62),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SheetField(
              controller: _loginController,
              label: 'Логин',
              icon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            _SheetField(
              controller: _passwordController,
              label: 'Пароль',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!isLoading) {
                  _submitLogin();
                }
              },
            ),
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_errorMessage,
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: Colors.white)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: KundiPalette.deepIndigo,
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: isLoading ? null : _submitLogin,
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Продолжить'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitLogin() {
    if (_completionHandled ||
        _loginPending ||
        ref.read(authControllerProvider).isLoading) {
      return;
    }
    setState(() {
      _loginPending = true;
      _errorMessage = '';
    });
    ref.read(authControllerProvider.notifier).login(
          source: widget.source,
          login: _loginController.text.trim(),
          password: _passwordController.text,
        );
  }

  String _sourceLabel(String source) {
    return switch (source) {
      'dnevnikru' => 'Dnevnik.ru',
      'edupage' => 'EduPage',
      _ => 'Kundelik.kz',
    };
  }

  void _logPostLoginStage({
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

  String _redactLogin(String login) {
    final normalized = login.trim();
    if (normalized.isEmpty) {
      return '<empty>';
    }
    if (normalized.length <= 2) {
      return '${normalized[0]}***';
    }
    return '${normalized.substring(0, 2)}***';
  }
}

class _SkyAccentLayer extends StatelessWidget {
  const _SkyAccentLayer();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(
          top: 132,
          left: 42,
          child: _StarDot(size: 3, color: Color(0xFF7D6CFF)),
        ),
        Positioned(
          top: 84,
          left: 122,
          child: _StarDot(size: 5, color: Color(0xFF8F63FF)),
        ),
        Positioned(
          top: 162,
          right: 72,
          child: _StarDot(size: 4, color: Color(0xFF8A79FF)),
        ),
        Positioned(
          top: 210,
          right: 24,
          child: _StarDot(size: 5, color: Color(0xFF9F87FF)),
        ),
        Positioned(
          top: 320,
          left: 250,
          child: _StarDot(size: 4, color: Color(0xFFAF93FF)),
        ),
        Positioned(
          top: 538,
          left: 34,
          child: _StarDot(size: 3, color: Color(0xFF7568E9)),
        ),
        Positioned(
          top: 694,
          left: 102,
          child: _StarDot(size: 4, color: Color(0xFF8E72FF)),
        ),
        Positioned(
          top: 852,
          right: 48,
          child: _StarDot(size: 3, color: Color(0xFFA68BFF)),
        ),
      ],
    );
  }
}

class _StarDot extends StatelessWidget {
  const _StarDot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 2,
      height: size * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.65),
            blurRadius: size * 5,
          ),
        ],
      ),
    );
  }
}

class _LogoBlock extends StatelessWidget {
  const _LogoBlock({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Transform.scale(
      scale: scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/logo.webp',
            width: 232,
            height: 64,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 6),
          Text(
            'Ваш электронный дневник',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFC8C3F0),
              fontWeight: FontWeight.w500,
              fontSize: 15.0,
              height: 0.98,
            ),
          ),
          const SizedBox(height: 2),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFFC8C3F0),
                fontWeight: FontWeight.w500,
                fontSize: 15.0,
                height: 0.98,
              ),
              children: const [
                TextSpan(text: 'с '),
                TextSpan(
                  text: 'ИИ-репетитором',
                  style: TextStyle(
                    color: Color(0xFFA46BFF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    required this.width,
    required this.heightFactor,
  });

  final double width;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _SpeechBubblePainter(),
      child: SizedBox(
        width: width,
        height: width * heightFactor,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Привет!',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.2,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const _StarDot(size: 4, color: Color(0xFF9B7BFF)),
                ],
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFC8C3F0),
                    fontSize: 11.5,
                    height: 1.26,
                    fontWeight: FontWeight.w500,
                  ),
                  children: const [
                    TextSpan(text: 'Я '),
                    TextSpan(
                      text: 'Kundi',
                      style: TextStyle(
                        color: Color(0xFFA46BFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: ', ваш\nИИ-репетитор'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeechBubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bubblePath = Path()
      ..moveTo(26, 0)
      ..lineTo(size.width - 34, 0)
      ..quadraticBezierTo(size.width, 0, size.width, 28)
      ..lineTo(size.width, size.height * 0.42)
      ..quadraticBezierTo(
        size.width,
        size.height * 0.58,
        size.width + 16,
        size.height * 0.61,
      )
      ..quadraticBezierTo(
        size.width - 2,
        size.height * 0.64,
        size.width - 8,
        size.height * 0.73,
      )
      ..lineTo(size.width - 8, size.height - 28)
      ..quadraticBezierTo(
          size.width - 8, size.height, size.width - 36, size.height)
      ..lineTo(26, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - 28)
      ..lineTo(0, 28)
      ..quadraticBezierTo(0, 0, 26, 0)
      ..close();

    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x422B2767),
          Color(0x28363274),
        ],
      ).createShader(Offset.zero & size);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0x665F56C9);

    canvas.drawShadow(
      bubblePath,
      const Color(0xFF36226E).withValues(alpha: 0.46),
      18,
      false,
    );
    canvas.drawPath(bubblePath, fill);
    canvas.drawPath(bubblePath, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BackgroundOrbitRings extends StatelessWidget {
  const _BackgroundOrbitRings();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BackgroundOrbitRingsPainter(),
      size: Size.infinite,
    );
  }
}

class _BackgroundOrbitRingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.50, size.height * 0.50);
    for (final radius in [
      size.width * 0.46,
      size.width * 0.62,
      size.width * 0.79
    ]) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF5A47C8).withValues(alpha: 0.20);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AuthSelectionCard extends StatelessWidget {
  const _AuthSelectionCard({
    required this.isLoading,
    required this.onSelectSource,
  });

  final bool isLoading;
  final ValueChanged<String> onSelectSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF291F58).withValues(alpha: 0.22),
            const Color(0xFF171437).withValues(alpha: 0.20),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                    border: Border.all(
                      color: const Color(0xFF7159E7).withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFFD8CCFF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15.9,
                            height: 1.0,
                          ),
                          children: const [
                            TextSpan(text: 'Войдите через ваш\n'),
                            TextSpan(
                              text: 'электронный дневник',
                              style: TextStyle(
                                color: Color(0xFFA46BFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Выберите сервис для входа',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFB6B0DF),
                          fontSize: 10.9,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProviderButton(
              source: 'kundelik',
              title: 'Войти через Kundelik.kz',
              onTap: isLoading ? null : () => onSelectSource('kundelik'),
            ),
            const SizedBox(height: 9),
            _ProviderButton(
              source: 'dnevnikru',
              title: 'Войти через Dnevnik.ru',
              onTap: isLoading ? null : () => onSelectSource('dnevnikru'),
            ),
            const SizedBox(height: 9),
            _ProviderButton(
              source: 'edupage',
              title: 'Войти через EduPage',
              onTap: isLoading ? null : () => onSelectSource('edupage'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF7D4BFF).withValues(alpha: 0.16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7D4BFF).withValues(alpha: 0.28),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    color: Color(0xFFA46BFF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Безопасно и надежно',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: const Color(0xFFA46BFF),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Мы не храним пароль от дневника',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFA8A2CE),
                          fontSize: 10.4,
                          height: 1.08,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.source,
    required this.title,
    required this.onTap,
  });

  final String source;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF40386D).withValues(alpha: 0.17),
                const Color(0xFF232044).withValues(alpha: 0.15),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 20,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.18),
                          Colors.white.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _ProviderMark(source: source, compact: true),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  title,
                                  textAlign: TextAlign.left,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13.8,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: const Color(0xFFA39AD7).withValues(alpha: 0.92),
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderMark extends StatelessWidget {
  const _ProviderMark({
    required this.source,
    required this.compact,
  });

  final String source;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 34.0 : 40.0;
    final label = switch (source) {
      'dnevnikru' => 'D',
      'edupage' => 'E',
      _ => 'K',
    };
    final textColor = switch (source) {
      'dnevnikru' => const Color(0xFF2196F3),
      'edupage' => const Color(0xFF7BCB24),
      _ => const Color(0xFF3D6BFF),
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: compact ? 22 : 24,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _SheetGlass extends StatelessWidget {
  const _SheetGlass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF20174B).withValues(alpha: 0.96),
            const Color(0xFF120F34).withValues(alpha: 0.96),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: child,
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, size: 20, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.10),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFFE0D7FF),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}
