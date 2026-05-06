class ConnectorException implements Exception {
  const ConnectorException({
    required this.code,
    required this.message,
    this.details = const <String, dynamic>{},
  });

  final String code;
  final String message;
  final Map<String, dynamic> details;

  @override
  String toString() => 'ConnectorException($code): $message';
}
