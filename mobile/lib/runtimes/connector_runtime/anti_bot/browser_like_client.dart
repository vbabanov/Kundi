import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'connector_http_client.dart';

class BrowserLikeClient implements ConnectorHttpClient {
  BrowserLikeClient(this._dio);

  final Dio _dio;
  final Map<String, Map<String, String>> _cookiesByDomain =
      <String, Map<String, String>>{};

  @override
  Future<ConnectorHttpResponse> get(
    String url, {
    Map<String, dynamic>? query,
  }) async {
    _emitDiaryRequestShape(url: url, query: query);
    final response = await _dio.get(
      url,
      queryParameters: query,
      options: _browserOptions(
        url: url,
        isLoginPost: false,
      ),
    );
    _rememberCookies(response.headers.map, response.realUri.host);
    return ConnectorHttpResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
      headers: response.headers.map,
      effectiveUri: response.realUri.toString(),
    );
  }

  @override
  Future<ConnectorHttpResponse> post(
    String url, {
    Object? data,
  }) async {
    final response = await _dio.post(
      url,
      data: data,
      options: _browserOptions(
        url: url,
        isLoginPost: true,
      ),
    );
    _rememberCookies(response.headers.map, response.realUri.host);
    return ConnectorHttpResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
      headers: response.headers.map,
      effectiveUri: response.realUri.toString(),
    );
  }

  Options _browserOptions({
    required String url,
    required bool isLoginPost,
  }) {
    final uri = Uri.parse(url);
    final isApiRequest = uri.path.toLowerCase().startsWith('/api/');
    final cookieHeader = _buildCookieHeader(uri.host.toLowerCase());
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
      'Accept': isApiRequest
          ? 'application/json, text/plain, */*'
          : 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'ru-RU,ru;q=0.9,en;q=0.8',
      'Origin': '${uri.scheme}://${uri.host}',
      'Referer': isApiRequest
          ? '${uri.scheme}://kundelik.kz/'
          : '${uri.scheme}://${uri.host}/',
    };
    if (isApiRequest) {
      headers['X-Requested-With'] = 'XMLHttpRequest';
    }
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    return Options(
      headers: headers,
      responseType: ResponseType.plain,
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
      contentType: isLoginPost ? Headers.formUrlEncodedContentType : null,
    );
  }

  void _rememberCookies(Map<String, List<String>> headers, String host) {
    final setCookie = headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) {
      return;
    }
    final normalizedHost = host.toLowerCase();
    for (final entry in setCookie) {
      final parts = entry
          .split(';')
          .map((part) => part.trim())
          .where((p) => p.isNotEmpty);
      if (parts.isEmpty) {
        continue;
      }
      final pair = parts.first.split('=');
      if (pair.length != 2) {
        continue;
      }
      final cookieName = pair[0].trim();
      final cookieValue = pair[1].trim();
      if (cookieName.isEmpty || cookieValue.isEmpty) {
        continue;
      }
      String domain = normalizedHost;
      for (final attr in parts.skip(1)) {
        final idx = attr.indexOf('=');
        if (idx <= 0) {
          continue;
        }
        final attrName = attr.substring(0, idx).trim().toLowerCase();
        final attrValue = attr.substring(idx + 1).trim().toLowerCase();
        if (attrName == 'domain' && attrValue.isNotEmpty) {
          domain =
              attrValue.startsWith('.') ? attrValue.substring(1) : attrValue;
        }
      }

      _cookiesByDomain.putIfAbsent(
          domain, () => <String, String>{})[cookieName] = cookieValue;
    }
  }

  String? _buildCookieHeader(String requestHost) {
    final merged = <String, String>{};
    for (final entry in _cookiesByDomain.entries) {
      final domain = entry.key;
      final applies = requestHost == domain || requestHost.endsWith('.$domain');
      if (!applies) {
        continue;
      }
      merged.addAll(entry.value);
    }
    if (merged.isEmpty) {
      return null;
    }
    return merged.entries.map((item) => '${item.key}=${item.value}').join('; ');
  }

  void _emitDiaryRequestShape({
    required String url,
    required Map<String, dynamic>? query,
  }) {
    final uri = Uri.parse(url);
    if (uri.path != '/api/v2/marks/diary') {
      return;
    }
    final q = <String, String>{};
    (query ?? const <String, dynamic>{}).forEach((key, value) {
      q[key] = value?.toString() ?? '';
    });
    final requestUri = uri.replace(queryParameters: q.isEmpty ? null : q);
    debugPrint(
      '[KUNDI_LIVE][kundelik_diary_request_shape] ${requestUri.toString()}',
    );
    debugPrint(
      '[KUNDI_LIVE][kundelik_diary_request_params] ${q.toString()}',
    );
  }
}
