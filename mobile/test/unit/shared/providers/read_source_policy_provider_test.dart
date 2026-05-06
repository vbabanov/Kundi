import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/network/read_source_policy.dart';
import 'package:kundi_mobile/shared/providers/providers.dart';

void main() {
  test('readSourcePolicyProvider defaults to v2 enabled', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final policy = container.read(readSourcePolicyProvider);
    expect(policy.useTypedV2Read, isTrue);

    final decision =
        policy.typedV2Decision(studentId: '1f583b87-af32-4e2b-a336-41daa7f05133');
    expect(decision.mode, ReadSourceMode.v2);
    expect(decision.reason, 'global_v2_enabled');
  });
}
