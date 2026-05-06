import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import 'ingest_uploader.dart';

class ApiIngestUploader implements IngestUploader {
  ApiIngestUploader(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<void> uploadBundle({
    required String accessToken,
    required Map<String, dynamic> payload,
  }) async {
    final endpoint = _ingestEndpoint(payload);
    final response = await _apiClient.post(
      endpoint,
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      data: payload,
    );
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'ingest upload failed with status ${response.statusCode}',
      );
    }
  }

  String _ingestEndpoint(Map<String, dynamic> payload) {
    final versionRaw = payload['contract_version'];
    final version = int.tryParse((versionRaw ?? '').toString()) ?? 1;
    return version == 2 ? '/v2/ingest/bundle' : '/v1/ingest/bundle';
  }
}
