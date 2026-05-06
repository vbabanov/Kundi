import '../../../runtimes/connector_runtime/contracts/models.dart';
import 'auth_session.dart';

abstract class AuthRepository {
  Future<AuthSession> login({required DiaryAuthCredentials credentials});
  Future<AuthSession?> tryAutoLogin();
  Future<Map<String, String>> loadSavedCredentials();
}
