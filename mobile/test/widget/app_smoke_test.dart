import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kundi_mobile/app/app.dart';

void main() {
  testWidgets('Kundi app boots', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KundiApp()));
    await tester.pumpAndSettle();

    expect(find.text('Kundi Login'), findsOneWidget);
  });
}
