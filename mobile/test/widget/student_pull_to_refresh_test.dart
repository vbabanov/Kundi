import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/l10n/generated/app_localizations.dart';
import 'package:kundi_mobile/shared/widgets/student_pull_to_refresh.dart';

void main() {
  testWidgets('a successful retry dismisses the previous failure snackbar',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studentRefreshActionProvider.overrideWithValue(() async {
            attempts += 1;
            if (attempts == 1) {
              throw StateError('controlled refresh failure');
            }
          }),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => refreshStudentFromGesture(context, ref),
                child: const Text('refresh'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('refresh'));
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось обновить данные. Старые данные сохранены.'),
      findsOneWidget,
    );

    await tester.tap(find.text('refresh'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
      find.text('Не удалось обновить данные. Старые данные сохранены.'),
      findsNothing,
    );
  });
}
