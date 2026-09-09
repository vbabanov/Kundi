import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_session.dart';
import '../domain/gamification_entity.dart';
import '../domain/gamification_repository.dart';

class GamificationRepositoryImpl implements GamificationRepository {
  GamificationRepositoryImpl({
    required ApiClient apiClient,
    required AuthSession? Function() readSession,
  }) : _apiClient = apiClient,
       _readSession = readSession;

  final ApiClient _apiClient;
  final AuthSession? Function() _readSession;

  @override
  Future<GamificationProfile> getProfile() async {
    final response = await _apiClient.get(
      '/v1/gamification/profile',
      options: _authorizedOptions(),
    );
    return _mapProfile(response);
  }

  @override
  Future<GamificationProfile> recordActivity() async {
    final response = await _apiClient.post(
      '/v1/gamification/activity',
      data: const <String, dynamic>{},
      options: _authorizedOptions(),
    );
    return _mapProfile(response);
  }

  @override
  Future<void> acknowledge(List<String> achievementCodes) async {
    if (achievementCodes.isEmpty) return;
    final response = await _apiClient.post(
      '/v1/gamification/achievements/ack',
      data: <String, dynamic>{'codes': achievementCodes},
      options: _authorizedOptions(),
    );
    if (response.statusCode != 204) {
      throw const AppException(
        'gamification_ack_failed',
        'Unable to acknowledge achievements.',
      );
    }
  }

  Options _authorizedOptions() {
    final session = _readSession();
    if (session == null || session.accessToken.trim().isEmpty) {
      throw const AppException(
        'not_authenticated',
        'Please login again before loading achievements.',
      );
    }
    return Options(
      headers: <String, String>{
        'Authorization': 'Bearer ${session.accessToken}',
      },
    );
  }

  GamificationProfile _mapProfile(Response<dynamic> response) {
    if (response.statusCode != 200 || response.data is! Map) {
      throw const AppException(
        'gamification_load_failed',
        'Unable to load achievements.',
      );
    }
    final envelope = Map<String, dynamic>.from(response.data as Map);
    final raw = envelope['data'];
    if (raw is! Map) {
      throw const AppException(
        'gamification_invalid_response',
        'Achievement data is invalid.',
      );
    }
    final profile = GamificationProfile.fromJson(
      Map<String, dynamic>.from(raw),
    );
    if (profile.catalogVersion < 1 || profile.achievementsTotal < 0) {
      throw const AppException(
        'gamification_invalid_response',
        'Achievement data is invalid.',
      );
    }
    return profile;
  }
}
