class RawPayloadRepository {
  RawPayloadRepository({
    int? maxRecords,
    Duration? recordTtl,
    int? maxStringLength,
    DateTime Function()? now,
  })  : _maxRecords = maxRecords ?? 200,
        _recordTtl = recordTtl ?? const Duration(hours: 24),
        _maxStringLength = maxStringLength ?? 512,
        _now = now ?? (() => DateTime.now().toUtc());

  final int _maxRecords;
  final Duration _recordTtl;
  final int _maxStringLength;
  final DateTime Function() _now;
  final List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  static const Set<String> _sensitiveKeyTokens = <String>{
    'password',
    'cookie',
    'token',
    'authorization',
    'secret',
  };

  void store(
      {required String operation, required Map<String, dynamic> payload}) {
    _pruneExpired();
    _records.add({
      'operation': operation,
      'payload': _sanitizeMap(payload),
      'captured_at': _now().toIso8601String(),
    });
    if (_records.length > _maxRecords) {
      _records.removeRange(0, _records.length - _maxRecords);
    }
  }

  List<Map<String, dynamic>> snapshot() {
    _pruneExpired();
    return List.unmodifiable(_records);
  }

  void clear() => _records.clear();

  void _pruneExpired() {
    final cutoff = _now().subtract(_recordTtl);
    _records.removeWhere((record) {
      final raw = (record['captured_at'] ?? '').toString();
      final capturedAt = DateTime.tryParse(raw)?.toUtc();
      if (capturedAt == null) {
        return true;
      }
      return capturedAt.isBefore(cutoff);
    });
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> payload) {
    final out = <String, dynamic>{};
    payload.forEach((key, value) {
      final keyLower = key.toLowerCase();
      if (_isSensitiveKey(keyLower)) {
        out[key] = '<redacted>';
        return;
      }
      if (keyLower == 'body' || keyLower.endsWith('_body')) {
        out[key] = _summarizeBody(value);
        return;
      }
      out[key] = _sanitizeValue(value, depth: 0, key: keyLower);
    });
    return out;
  }

  dynamic _sanitizeValue(dynamic value, {required int depth, String key = ''}) {
    if (depth > 4) {
      return '<truncated_depth>';
    }
    if (value is Map) {
      final map = <String, dynamic>{};
      var count = 0;
      for (final entry in value.entries) {
        if (count >= 40) {
          map['__truncated__'] = true;
          break;
        }
        final childKey = entry.key.toString();
        final childKeyLower = childKey.toLowerCase();
        if (_isSensitiveKey(childKeyLower)) {
          map[childKey] = '<redacted>';
        } else {
          map[childKey] = _sanitizeValue(
            entry.value,
            depth: depth + 1,
            key: childKeyLower,
          );
        }
        count++;
      }
      return map;
    }
    if (value is List) {
      final maxItems = value.length > 40 ? 40 : value.length;
      final items = value
          .take(maxItems)
          .map((item) => _sanitizeValue(item, depth: depth + 1, key: key))
          .toList(growable: false);
      if (value.length > maxItems) {
        return <dynamic>[
          ...items,
          '<truncated_list:${value.length - maxItems} >'
        ];
      }
      return items;
    }
    if (value is String) {
      return _truncate(value);
    }
    return value;
  }

  dynamic _summarizeBody(dynamic body) {
    if (body is String) {
      return _truncate(body);
    }
    if (body is Map) {
      return <String, dynamic>{
        'kind': 'map',
        'keys': body.keys.take(10).map((key) => key.toString()).toList(),
        'size': body.length,
      };
    }
    if (body is List) {
      return <String, dynamic>{'kind': 'list', 'size': body.length};
    }
    return _truncate(body.toString());
  }

  bool _isSensitiveKey(String keyLower) {
    for (final token in _sensitiveKeyTokens) {
      if (keyLower.contains(token)) {
        return true;
      }
    }
    return false;
  }

  String _truncate(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= _maxStringLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, _maxStringLength)}<truncated>';
  }
}
