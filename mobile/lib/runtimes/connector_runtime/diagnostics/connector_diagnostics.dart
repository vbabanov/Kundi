enum ConnectorDiagnosticLevel {
  info,
  warning,
  error,
}

class ConnectorDiagnosticEvent {
  const ConnectorDiagnosticEvent({
    required this.timestamp,
    required this.level,
    required this.code,
    required this.message,
    required this.details,
  });

  final DateTime timestamp;
  final ConnectorDiagnosticLevel level;
  final String code;
  final String message;
  final Map<String, dynamic> details;

  String toLine() {
    final levelName = level.name.toUpperCase();
    return '[${timestamp.toIso8601String()}][$levelName][$code] $message';
  }
}

class ConnectorDiagnostics {
  final List<ConnectorDiagnosticEvent> _events = <ConnectorDiagnosticEvent>[];

  void record(
    String message, {
    String code = 'connector_event',
    ConnectorDiagnosticLevel level = ConnectorDiagnosticLevel.info,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) {
    _events.add(
      ConnectorDiagnosticEvent(
        timestamp: DateTime.now().toUtc(),
        level: level,
        code: code,
        message: message,
        details: details,
      ),
    );
  }

  List<String> export() =>
      _events.map((event) => event.toLine()).toList(growable: false);

  List<ConnectorDiagnosticEvent> exportEvents() => List.unmodifiable(_events);
}
