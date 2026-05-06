import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';

enum HomeworkDayDigestMode {
  homework('homework'),
  topic('topic');

  const HomeworkDayDigestMode(this.apiValue);
  final String apiValue;
}

enum WhatsappDispatchStatus {
  sent('sent'),
  queued('queued'),
  failed('failed');

  const WhatsappDispatchStatus(this.apiValue);
  final String apiValue;

  static WhatsappDispatchStatus fromApi(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'sent':
        return WhatsappDispatchStatus.sent;
      case 'failed':
        return WhatsappDispatchStatus.failed;
      default:
        return WhatsappDispatchStatus.queued;
    }
  }
}

class HomeworkDayWhatsappRequest {
  const HomeworkDayWhatsappRequest({
    required this.accessToken,
    required this.date,
    required this.mode,
    required this.idempotencyKey,
  });

  final String accessToken;
  final String date;
  final HomeworkDayDigestMode mode;
  final String idempotencyKey;
}

class HomeworkDayWhatsappResult {
  const HomeworkDayWhatsappResult({
    required this.jobId,
    required this.created,
    required this.status,
    required this.message,
  });

  final String jobId;
  final bool created;
  final WhatsappDispatchStatus status;
  final String message;
}

class HomeworkDayWhatsappRepository {
  HomeworkDayWhatsappRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<HomeworkDayWhatsappResult> sendDayDigest(
    HomeworkDayWhatsappRequest request,
  ) async {
    if (request.accessToken.trim().isEmpty) {
      throw const AppException(
        'whatsapp_auth_required',
        'Сессия недействительна. Выполните вход снова.',
      );
    }
    if (request.date.trim().isEmpty) {
      throw const AppException(
        'whatsapp_date_required',
        'Не выбрана дата для отправки.',
      );
    }

    final enqueueResponse = await _enqueueDayDigest(request);
    final payload = _extractPayload(enqueueResponse.data);
    final jobId = (payload['job_id'] ?? '').toString().trim();
    if (jobId.isEmpty) {
      throw const AppException(
        'whatsapp_day_send_failed',
        'Сервис WhatsApp вернул неполный ответ.',
      );
    }

    final statusResult = await _waitForFinalStatus(
      accessToken: request.accessToken,
      jobId: jobId,
    );
    if (statusResult.status == WhatsappDispatchStatus.failed) {
      throw AppException(
        'whatsapp_day_send_failed',
        statusResult.message.isEmpty
            ? 'Не удалось отправить сообщение в WhatsApp.'
            : statusResult.message,
      );
    }

    return HomeworkDayWhatsappResult(
      jobId: jobId,
      created: payload['created'] == true,
      status: statusResult.status,
      message: statusResult.message,
    );
  }

  Future<Response<dynamic>> _enqueueDayDigest(
    HomeworkDayWhatsappRequest request,
  ) async {
    try {
      return await _apiClient.post(
        '/v1/whatsapp/send-homework',
        options: Options(
          contentType: Headers.jsonContentType,
          headers: <String, String>{
            'Authorization': 'Bearer ${request.accessToken}',
            'X-Idempotency-Key': request.idempotencyKey,
          },
        ),
        data: <String, dynamic>{
          'date': request.date.trim(),
          'mode': request.mode.apiValue,
        },
      );
    } on DioException catch (error) {
      throw AppException(
        'whatsapp_day_send_failed',
        _errorMessageFromDio(error),
      );
    }
  }

  Future<_WhatsappJobStatus> _waitForFinalStatus({
    required String accessToken,
    required String jobId,
  }) async {
    const attempts = 8;
    for (var i = 0; i < attempts; i++) {
      final status =
          await _loadJobStatus(accessToken: accessToken, jobId: jobId);
      if (status.status != WhatsappDispatchStatus.queued || i == attempts - 1) {
        return status;
      }
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
    return const _WhatsappJobStatus(
      status: WhatsappDispatchStatus.queued,
      message: 'Отправка поставлена в очередь и ещё выполняется.',
    );
  }

  Future<_WhatsappJobStatus> _loadJobStatus({
    required String accessToken,
    required String jobId,
  }) async {
    try {
      final response = await _apiClient.get(
        '/v1/whatsapp/jobs/$jobId',
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );
      final payload = _extractPayload(response.data);
      final status = WhatsappDispatchStatus.fromApi(
        (payload['status'] ?? '').toString(),
      );
      final lastError = (payload['last_error'] ?? '').toString().trim();
      if (status == WhatsappDispatchStatus.sent) {
        return const _WhatsappJobStatus(
          status: WhatsappDispatchStatus.sent,
          message: 'Сообщение отправлено в WhatsApp.',
        );
      }
      if (status == WhatsappDispatchStatus.failed) {
        return _WhatsappJobStatus(
          status: WhatsappDispatchStatus.failed,
          message: lastError.isEmpty
              ? 'WhatsApp отправка завершилась ошибкой.'
              : lastError,
        );
      }
      return const _WhatsappJobStatus(
        status: WhatsappDispatchStatus.queued,
        message: 'Отправка поставлена в очередь и ещё выполняется.',
      );
    } on DioException catch (error) {
      return _WhatsappJobStatus(
        status: WhatsappDispatchStatus.queued,
        message: _errorMessageFromDio(error),
      );
    }
  }

  Map<String, dynamic> _extractPayload(dynamic data) {
    if (data is Map && data['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return const <String, dynamic>{};
  }

  String _errorMessageFromDio(DioException error) {
    String message = 'Не удалось отправить сообщение в WhatsApp.';
    final responseData = error.response?.data;
    if (responseData is Map && responseData['error'] is Map) {
      final apiMessage = (responseData['error']['message'] ?? '').toString();
      if (apiMessage.trim().isNotEmpty) {
        message = apiMessage.trim();
      }
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      message =
          'Превышено время ожидания отправки. Проверьте интернет и повторите.';
    }
    return message;
  }
}

class _WhatsappJobStatus {
  const _WhatsappJobStatus({
    required this.status,
    required this.message,
  });

  final WhatsappDispatchStatus status;
  final String message;
}
