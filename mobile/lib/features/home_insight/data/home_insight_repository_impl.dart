import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_session.dart';
import '../domain/home_insight.dart';
import '../domain/home_insight_repository.dart';

class HomeInsightRepositoryImpl implements HomeInsightRepository {
  HomeInsightRepositoryImpl({
    required ApiClient apiClient,
    required AuthSession? Function() readSession,
  })  : _apiClient = apiClient,
        _readSession = readSession;

  final ApiClient _apiClient;
  final AuthSession? Function() _readSession;

  @override
  Future<HomeInsight> getInsight({required String locale}) async {
    final session = _readSession();
    if (session == null || session.accessToken.trim().isEmpty) {
      throw const AppException(
        'not_authenticated',
        'Please login again before loading the home insight.',
      );
    }
    final response = await _apiClient.get(
      '/v1/home/insight',
      queryParameters: <String, dynamic>{'locale': locale},
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${session.accessToken}',
        },
      ),
    );
    if (response.statusCode != 200 || response.data is! Map) {
      throw const AppException(
        'home_insight_load_failed',
        'Unable to load the home insight.',
      );
    }
    final envelope = Map<String, dynamic>.from(response.data as Map);
    final raw = envelope['data'];
    if (raw is! Map) {
      throw const AppException(
        'home_insight_invalid_response',
        'Home insight data is invalid.',
      );
    }
    try {
      final insight = HomeInsight.fromJson(Map<String, dynamic>.from(raw));
      if (insight.locale != locale) {
        throw const FormatException('home insight locale mismatch');
      }
      return insight;
    } on FormatException catch (error) {
      throw AppException(
        'home_insight_invalid_response',
        'Home insight data is invalid: ${error.message}',
      );
    }
  }
}
