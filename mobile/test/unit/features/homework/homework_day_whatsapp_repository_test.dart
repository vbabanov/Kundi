import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/errors/app_exception.dart';
import 'package:kundi_mobile/core/network/api_client.dart';
import 'package:kundi_mobile/features/homework/data/homework_day_whatsapp_repository.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('sends selected date in JSON body and resolves sent status', () async {
    Map<String, dynamic>? capturedBody;
    server.listen((request) async {
      if (request.method == 'POST' &&
          request.uri.path == '/v1/whatsapp/send-homework') {
        capturedBody = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        request.response.statusCode = 202;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {'job_id': 'job-123', 'created': true, 'status': 'queued'}
        }));
        await request.response.close();
        return;
      }
      if (request.method == 'GET' &&
          request.uri.path == '/v1/whatsapp/jobs/job-123') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {
            'job_id': 'job-123',
            'status': 'sent',
            'job_status': 'succeeded',
          }
        }));
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final repository = HomeworkDayWhatsappRepository(
      apiClient: ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'),
    );
    final result = await repository.sendDayDigest(
      const HomeworkDayWhatsappRequest(
        accessToken: 'token',
        date: '2026-04-17',
        mode: HomeworkDayDigestMode.homework,
        idempotencyKey: 'wh-day-homework-2026-04-17',
      ),
    );

    expect(capturedBody?['date'], '2026-04-17');
    expect(capturedBody?['mode'], 'homework');
    expect(result.status, WhatsappDispatchStatus.sent);
  });

  test('returns provider failure reason from status endpoint', () async {
    server.listen((request) async {
      if (request.method == 'POST' &&
          request.uri.path == '/v1/whatsapp/send-homework') {
        request.response.statusCode = 202;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {'job_id': 'job-err', 'created': true, 'status': 'queued'}
        }));
        await request.response.close();
        return;
      }
      if (request.method == 'GET' &&
          request.uri.path == '/v1/whatsapp/jobs/job-err') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {
            'job_id': 'job-err',
            'status': 'failed',
            'job_status': 'dead_letter',
            'last_error':
                'WhatsApp не подключён. Подключите WhatsApp через QR.',
          }
        }));
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final repository = HomeworkDayWhatsappRepository(
      apiClient: ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'),
    );
    await expectLater(
      () => repository.sendDayDigest(
        const HomeworkDayWhatsappRequest(
          accessToken: 'token',
          date: '2026-04-17',
          mode: HomeworkDayDigestMode.topic,
          idempotencyKey: 'wh-day-topic-2026-04-17',
        ),
      ),
      throwsA(
        isA<AppException>().having(
          (error) => error.message,
          'message',
          contains('WhatsApp не подключён'),
        ),
      ),
    );
  });
}
