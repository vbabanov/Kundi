import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/raw_payload/raw_payload_repository.dart';

void main() {
  test('raw payload repository redacts sensitive fields and truncates body',
      () {
    final repository = RawPayloadRepository(maxStringLength: 32);

    repository.store(
      operation: 'kundelik.authenticate',
      payload: {
        'login': 'student-login',
        'password': 'super-secret-password',
        'set-cookie': 'sessionid=abc123',
        'body': 'x' * 200,
      },
    );

    final snapshot = repository.snapshot();
    expect(snapshot.length, 1);

    final payload = Map<String, dynamic>.from(
        snapshot.first['payload'] as Map<dynamic, dynamic>);
    expect(payload['password'], '<redacted>');
    expect(payload['set-cookie'], '<redacted>');
    expect((payload['body'] as String).contains('<truncated>'), isTrue);
  });

  test('raw payload repository prunes records older than ttl', () {
    var now = DateTime.utc(2026, 3, 30, 10, 0, 0);
    final repository = RawPayloadRepository(
      recordTtl: const Duration(minutes: 5),
      now: () => now,
    );

    repository.store(operation: 'op-1', payload: {'status': 200});
    now = now.add(const Duration(minutes: 6));
    repository.store(operation: 'op-2', payload: {'status': 201});

    final snapshot = repository.snapshot();
    expect(snapshot.length, 1);
    expect(snapshot.first['operation'], 'op-2');
  });
}
