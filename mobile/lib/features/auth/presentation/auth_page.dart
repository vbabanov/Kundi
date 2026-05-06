import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  String _source = 'kundelik';
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_prefillSavedCredentials);
  }

  Future<void> _prefillSavedCredentials() async {
    if (_prefilled) {
      return;
    }
    _prefilled = true;
    final saved =
        await ref.read(authControllerProvider.notifier).loadSavedCredentials();
    if (!mounted) {
      return;
    }
    final savedSource = (saved['source'] ?? '').trim();
    final savedLogin = (saved['login'] ?? '').trim();
    final savedPassword = (saved['password'] ?? '').trim();
    setState(() {
      if (savedSource.isNotEmpty) {
        _source = savedSource;
      }
      if (savedLogin.isNotEmpty) {
        _loginController.text = savedLogin;
      }
      if (savedPassword.isNotEmpty) {
        _passwordController.text = savedPassword;
      }
    });
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (session) {
          if (session != null && mounted) {
            _logPostLoginStage(
              stage: 'login_success_ui',
              outcome: 'success',
              details: {
                'source': _source,
                'login': _redactLogin(_loginController.text.trim()),
              },
            );
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Login successful')));
            _logPostLoginStage(
              stage: 'route_transition_result',
              outcome: 'handled_by_root_auth_state',
              details: {'target': 'app_home_router'},
            );
          }
        },
        error: (error, stackTrace) {
          _logPostLoginStage(
            stage: 'final_post_login_error',
            outcome: 'ui_error',
            details: {'error': _sanitizeError(error.toString())},
          );
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.toString())));
          }
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Kundi Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _source,
              items: const [
                DropdownMenuItem(value: 'kundelik', child: Text('Kundelik')),
                DropdownMenuItem(value: 'dnevnikru', child: Text('Dnevnik.ru')),
                DropdownMenuItem(value: 'edupage', child: Text('EduPage')),
              ],
              onChanged: (value) =>
                  setState(() => _source = value ?? 'kundelik'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _loginController,
              decoration: const InputDecoration(labelText: 'Login'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: authState.isLoading
                    ? null
                    : () {
                        ref.read(authControllerProvider.notifier).login(
                              source: _source,
                              login: _loginController.text.trim(),
                              password: _passwordController.text,
                            );
                      },
                child: authState.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Login'),
              ),
            ),
          ],
        ),
      ),
    );
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

  String _sanitizeError(String message) {
    final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 180) {
      return normalized;
    }
    return '${normalized.substring(0, 180)}...';
  }
}
