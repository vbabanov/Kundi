import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import 'homework_day_whatsapp_repository.dart';

class HomeworkWhatsappSendRequest {
  const HomeworkWhatsappSendRequest({
    required this.accessToken,
    required this.homeworkId,
    required this.filePath,
    required this.fileName,
    required this.caption,
    required this.parentPhones,
    required this.idempotencyKey,
  });

  final String accessToken;
  final String homeworkId;
  final String filePath;
  final String fileName;
  final String caption;
  final List<String> parentPhones;
  final String idempotencyKey;
}

class HomeworkWhatsappSendResult {
  const HomeworkWhatsappSendResult({
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

class HomeworkWhatsappSendRepository {
  HomeworkWhatsappSendRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<HomeworkWhatsappSendResult> sendPhoto(
    HomeworkWhatsappSendRequest request,
  ) async {
    if (request.accessToken.trim().isEmpty) {
      throw const AppException(
        'whatsapp_auth_required',
        'Требуется активная сессия для отправки в WhatsApp.',
      );
    }
    if (request.homeworkId.trim().isEmpty) {
      throw const AppException(
        'whatsapp_homework_required',
        'Не найден идентификатор домашнего задания.',
      );
    }
    if (request.parentPhones.isEmpty) {
      throw const AppException(
        'whatsapp_parent_phones_missing',
        'Укажите хотя бы один номер родителя в профиле.',
      );
    }
    final photoFile = File(request.filePath);
    if (!await photoFile.exists()) {
      throw const AppException(
        'whatsapp_photo_missing',
        'Временный файл фото недоступен. Снимите фото заново.',
      );
    }
    final bytes = await photoFile.readAsBytes();
    if (bytes.isEmpty) {
      throw const AppException(
        'whatsapp_photo_empty',
        'Фото повреждено. Снимите фото заново.',
      );
    }

    final fileBase64 = base64Encode(bytes);
    final Options requestOptions = Options(
      sendTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 120),
      headers: <String, String>{
        'Authorization': 'Bearer ${request.accessToken}',
        'X-Idempotency-Key': request.idempotencyKey,
      },
    );

    Response<dynamic> response;
    try {
      response = await _apiClient.post(
        '/v1/whatsapp/send-photo',
        options: requestOptions,
        data: <String, dynamic>{
          'homework_id': request.homeworkId.trim(),
          'file_name': request.fileName.trim(),
          'file_base64': fileBase64,
          'caption': request.caption.trim(),
          'parent_phones': request.parentPhones,
        },
      );
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      final errorData = error.response?.data;
      String message = 'Не удалось отправить фото.';

      if (error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionTimeout) {
        message =
            'Превышено время ожидания отправки. Проверьте интернет и попробуйте снова.';
      } else if (errorData is Map && errorData['error'] is Map) {
        final apiMessage = (errorData['error']['message'] ?? '').toString();
        if (apiMessage.trim().isNotEmpty) {
          message = apiMessage.trim();
        }
      }

      debugPrint(
        '[HOMEWORK_WHATSAPP_SEND_ERROR] type=${error.type} status=$statusCode message=${error.message}',
      );
      throw AppException('whatsapp_send_failed', message);
    }

    if (response.statusCode != 202 || response.data is! Map) {
      throw const AppException(
        'whatsapp_send_failed',
        'Не удалось поставить отправку в очередь WhatsApp.',
      );
    }
    final root = Map<String, dynamic>.from(response.data as Map);
    final payload = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    final jobId = (payload['job_id'] ?? '').toString();
    if (jobId.trim().isEmpty) {
      throw const AppException(
        'whatsapp_send_invalid_response',
        'Сервис WhatsApp вернул некорректный ответ.',
      );
    }
    final statusResult = await _waitForFinalStatus(
      accessToken: request.accessToken,
      jobId: jobId.trim(),
    );
    if (statusResult.status == WhatsappDispatchStatus.failed) {
      throw AppException(
        'whatsapp_send_failed',
        statusResult.message.isEmpty
            ? 'Не удалось отправить фото.'
            : statusResult.message,
      );
    }
    return HomeworkWhatsappSendResult(
      jobId: jobId,
      created: payload['created'] == true,
      status: statusResult.status,
      message: statusResult.message,
    );
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
          message: 'Фото отправлено в WhatsApp.',
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

  String _errorMessageFromDio(DioException error) {
    String message = 'Не удалось отправить фото в WhatsApp.';
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
          'Превышено время ожидания отправки. Проверьте интернет и попробуйте снова.';
    }
    return message;
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
}

class _WhatsappJobStatus {
  const _WhatsappJobStatus({
    required this.status,
    required this.message,
  });

  final WhatsappDispatchStatus status;
  final String message;
}
