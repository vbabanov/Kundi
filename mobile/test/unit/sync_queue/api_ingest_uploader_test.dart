import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/network/api_client.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/sync_queue/api_ingest_uploader.dart';

void main() {
  test(
      'ApiIngestUploader routes contract_version=2 payload to /v2/ingest/bundle',
      () async {
    late HttpServer server;
    var capturedPath = '';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      capturedPath = request.uri.path;
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true}));
      await request.response.close();
    });

    final uploader = ApiIngestUploader(
      ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'),
    );
    await uploader.uploadBundle(
      accessToken: 'token',
      payload: const {
        'contract_version': 2,
        'source': 'kundelik',
      },
    );
    await server.close(force: true);

    expect(capturedPath, '/v2/ingest/bundle');
  });

  test('ApiIngestUploader routes legacy payload to /v1/ingest/bundle',
      () async {
    late HttpServer server;
    var capturedPath = '';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      capturedPath = request.uri.path;
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true}));
      await request.response.close();
    });

    final uploader = ApiIngestUploader(
      ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'),
    );
    await uploader.uploadBundle(
      accessToken: 'token',
      payload: const {
        'source': 'kundelik',
      },
    );
    await server.close(force: true);

    expect(capturedPath, '/v1/ingest/bundle');
  });
}
