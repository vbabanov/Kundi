import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../runtimes/connector_runtime/contracts/models.dart';
import '../../../shared/providers/providers.dart';
import '../data/auth_repository_impl.dart';
import '../domain/auth_session.dart';

final authRepositoryProvider = Provider<AuthRepositoryImpl>((ref) {
  return AuthRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    secureStorage: ref.watch(secureStorageProvider),
    connectorRuntime: ref.watch(connectorRuntimeProvider),
    canonicalCacheStore: ref.watch(canonicalCacheStoreProvider),
    syncQueueService: ref.watch(syncQueueServiceProvider),
    syncOrchestrator: ref.watch(syncOrchestratorProvider),
    readSourcePolicy: ref.watch(readSourcePolicyProvider),
  );
});

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    return ref.read(authRepositoryProvider).tryAutoLogin();
  }

  Future<void> login({
    required String source,
    required String login,
    required String password,
  }) async {
    state = const AsyncLoading<AuthSession?>();

    state = await AsyncValue.guard(() async {
      try {
        return await ref.read(authRepositoryProvider).login(
              credentials: DiaryAuthCredentials(
                  source: source, login: login, password: password),
            );
      } catch (error) {
        debugPrint(
          '[KUNDI_POST_LOGIN] ${jsonEncode({
                'stage': 'final_post_login_error',
                'outcome': 'controller_error',
                'source': source,
                'login': _redactLogin(login),
                'error': _sanitizeError(error.toString()),
              })}',
        );
        rethrow;
      }
    });
  }

  Future<Map<String, String>> loadSavedCredentials() {
    return ref.read(authRepositoryProvider).loadSavedCredentials();
  }

  Future<AuthSession?> ensureSessionBaseline() async {
    final repository = ref.read(authRepositoryProvider);
    final current = state.valueOrNull;
    if (current == null) {
      final restoredFromStore = await repository.tryAutoLogin();
      state = AsyncData<AuthSession?>(restoredFromStore);
      return restoredFromStore;
    }
    final restored = await repository.ensureSessionBaseline(current);
    state = AsyncData<AuthSession?>(restored);
    return restored;
  }

  void adoptRefreshedSession(AuthSession session) {
    state = AsyncData<AuthSession?>(session);
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
