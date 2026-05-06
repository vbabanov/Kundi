import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/auth/data/parity_shadow.dart';

void main() {
  test('parity mismatch reason reports single dimension', () {
    expect(
      parityMismatchReason(
        countMatch: false,
        identityMatch: true,
        moodMatch: true,
        aggregateMatch: true,
      ),
      'count',
    );
    expect(
      parityMismatchReason(
        countMatch: true,
        identityMatch: false,
        moodMatch: true,
        aggregateMatch: true,
      ),
      'identity',
    );
    expect(
      parityMismatchReason(
        countMatch: true,
        identityMatch: true,
        moodMatch: false,
        aggregateMatch: true,
      ),
      'mood',
    );
    expect(
      parityMismatchReason(
        countMatch: true,
        identityMatch: true,
        moodMatch: true,
        aggregateMatch: false,
      ),
      'aggregate',
    );
  });

  test('parity mismatch reason reports mixed for multi-dimension drift', () {
    expect(
      parityMismatchReason(
        countMatch: false,
        identityMatch: false,
        moodMatch: true,
        aggregateMatch: false,
      ),
      'mixed',
    );
  });

  test('parity mismatch reason empty when all match', () {
    expect(
      parityMismatchReason(
        countMatch: true,
        identityMatch: true,
        moodMatch: true,
        aggregateMatch: true,
      ),
      '',
    );
  });
}
