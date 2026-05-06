import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  const SecureStorageService(this._storage);

  final FlutterSecureStorage _storage;

  static const _diaryLoginKey = 'diary_login';
  static const _diaryPasswordKey = 'diary_password';
  static const _diarySourceKey = 'diary_source';
  static const _sessionSecretKey = 'diary_session_secret';
  static const _authStudentIdKey = 'auth_student_id';
  static const _authAccessTokenKey = 'auth_access_token';
  static const _authRefreshTokenKey = 'auth_refresh_token';
  static const _authExpiresAtKey = 'auth_expires_at';

  Future<void> saveDiaryCredentials({
    required String source,
    required String login,
    required String password,
  }) async {
    await _storage.write(key: _diarySourceKey, value: source);
    await _storage.write(key: _diaryLoginKey, value: login);
    await _storage.write(key: _diaryPasswordKey, value: password);
  }

  Future<Map<String, String>> loadDiaryCredentials() async {
    return {
      'source': await _storage.read(key: _diarySourceKey) ?? '',
      'login': await _storage.read(key: _diaryLoginKey) ?? '',
      'password': await _storage.read(key: _diaryPasswordKey) ?? '',
    };
  }

  Future<void> saveSourceSessionSecret(String secret) {
    return _storage.write(key: _sessionSecretKey, value: secret);
  }

  Future<String> loadSourceSessionSecret() async {
    return await _storage.read(key: _sessionSecretKey) ?? '';
  }

  Future<void> saveAuthSession({
    required String studentId,
    required String accessToken,
    required String refreshToken,
    required String expiresAtIso,
  }) async {
    await _storage.write(key: _authStudentIdKey, value: studentId);
    await _storage.write(key: _authAccessTokenKey, value: accessToken);
    await _storage.write(key: _authRefreshTokenKey, value: refreshToken);
    await _storage.write(key: _authExpiresAtKey, value: expiresAtIso);
  }

  Future<Map<String, String>> loadAuthSession() async {
    return {
      'student_id': await _storage.read(key: _authStudentIdKey) ?? '',
      'access_token': await _storage.read(key: _authAccessTokenKey) ?? '',
      'refresh_token': await _storage.read(key: _authRefreshTokenKey) ?? '',
      'expires_at': await _storage.read(key: _authExpiresAtKey) ?? '',
    };
  }

  Future<void> clearAuthSession() async {
    await _storage.delete(key: _authStudentIdKey);
    await _storage.delete(key: _authAccessTokenKey);
    await _storage.delete(key: _authRefreshTokenKey);
    await _storage.delete(key: _authExpiresAtKey);
  }

  Future<void> clearAll() {
    return _storage.deleteAll();
  }
}
