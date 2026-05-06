class ConnectorHttpResponse {
  const ConnectorHttpResponse({
    required this.statusCode,
    required this.data,
    this.headers = const <String, List<String>>{},
    this.effectiveUri,
  });

  final int statusCode;
  final dynamic data;
  final Map<String, List<String>> headers;
  final String? effectiveUri;
}

abstract class ConnectorHttpClient {
  Future<ConnectorHttpResponse> get(
    String url, {
    Map<String, dynamic>? query,
  });

  Future<ConnectorHttpResponse> post(
    String url, {
    Object? data,
  });
}
