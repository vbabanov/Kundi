import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kundi_mobile/core/storage/secure_storage_service.dart';

class FakeSecureStorageService extends SecureStorageService {
  FakeSecureStorageService() : super(const FlutterSecureStorage());

  final Map<String, String> _store = <String, String>{};

  @override
  Future<void> saveDiaryCredentials({
    required String source,
    required String login,
    required String password,
  }) async {
    _store['diary_source'] = source;
    _store['diary_login'] = login;
    _store['diary_password'] = password;
  }

  @override
  Future<Map<String, String>> loadDiaryCredentials() async {
    return <String, String>{
      'source': _store['diary_source'] ?? '',
      'login': _store['diary_login'] ?? '',
      'password': _store['diary_password'] ?? '',
    };
  }

  @override
  Future<void> saveSourceSessionSecret(String secret) async {
    _store['diary_session_secret'] = secret;
  }

  @override
  Future<String> loadSourceSessionSecret() async {
    return _store['diary_session_secret'] ?? '';
  }

  @override
  Future<void> saveAuthSession({
    required String studentId,
    required String accessToken,
    required String refreshToken,
    required String expiresAtIso,
  }) async {
    _store['auth_student_id'] = studentId;
    _store['auth_access_token'] = accessToken;
    _store['auth_refresh_token'] = refreshToken;
    _store['auth_expires_at'] = expiresAtIso;
  }

  @override
  Future<Map<String, String>> loadAuthSession() async {
    return <String, String>{
      'student_id': _store['auth_student_id'] ?? '',
      'access_token': _store['auth_access_token'] ?? '',
      'refresh_token': _store['auth_refresh_token'] ?? '',
      'expires_at': _store['auth_expires_at'] ?? '',
    };
  }

  @override
  Future<void> clearAuthSession() async {
    _store.remove('auth_student_id');
    _store.remove('auth_access_token');
    _store.remove('auth_refresh_token');
    _store.remove('auth_expires_at');
  }

  @override
  Future<void> clearAll() async {
    _store.clear();
  }
}
