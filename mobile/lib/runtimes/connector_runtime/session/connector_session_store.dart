class ConnectorSession {
  const ConnectorSession({
    required this.source,
    required this.login,
    required this.cookies,
    required this.createdAt,
  });

  final String source;
  final String login;
  final Map<String, String> cookies;
  final DateTime createdAt;
}

class ConnectorSessionStore {
  ConnectorSessionStore({Duration? ttl})
      : _ttl = ttl ?? const Duration(hours: 8);

  final Duration _ttl;
  ConnectorSession? _session;

  void save(ConnectorSession session) {
    _session = session;
  }

  ConnectorSession? load() {
    final session = _session;
    if (session == null) {
      return null;
    }
    final age = DateTime.now().toUtc().difference(session.createdAt);
    if (age > _ttl) {
      _session = null;
      return null;
    }
    return session;
  }

  void clear() {
    _session = null;
  }
}
