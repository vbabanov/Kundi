class AuthSession {
  const AuthSession({
    required this.studentId,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String studentId;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}
