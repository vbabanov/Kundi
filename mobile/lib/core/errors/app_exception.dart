class AppException implements Exception {
  const AppException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Map<String, Object?>? details;

  @override
  String toString() => 'AppException(code: $code, message: $message)';
}
