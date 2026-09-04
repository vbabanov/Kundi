import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/assistant/assistant_feature.dart';

void main() {
  test('assistant feature flag defaults to false', () {
    expect(kundiAssistantEnabledByDefault, isFalse);
  });
}
