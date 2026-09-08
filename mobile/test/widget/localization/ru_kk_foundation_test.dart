import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/l10n/generated/app_localizations.dart';
import 'package:kundi_mobile/l10n/l10n.dart';

void main() {
  Future<void> pumpLocale(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const _LocaleCoverageHarness(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Russian baseline renders primary surfaces and localized date',
      (tester) async {
    await pumpLocale(tester, const Locale('ru'));

    for (final label in [
      'Войти через Kundelik.kz',
      'Главная',
      'Домашнее задание',
      'Оценки',
      'Профиль',
      'Спросите Kundi',
      'Повторить',
      'Настройки',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.textContaining('сентябр'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kazakh renders primary surfaces without text overflow',
      (tester) async {
    await pumpLocale(tester, const Locale('kk'));

    for (final label in [
      'Kundelik.kz арқылы кіру',
      'Басты бет',
      'Үй тапсырмасы',
      'Бағалар',
      'Профиль',
      'Kundi-ден сұраңыз',
      'Қайталау',
      'Баптаулар',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.textContaining('қыркүйек'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _LocaleCoverageHarness extends StatelessWidget {
  const _LocaleCoverageHarness();

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(strings.authKundelik),
          Text(strings.navHome),
          Text(strings.homeworkTitle),
          Text(strings.gradesTitle),
          Text(strings.profileTitle),
          Text(strings.assistantTitle),
          Text(strings.commonRetry),
          Text(strings.settingsTitle),
          Text(context.formatFullDate(DateTime(2026, 9, 8))),
        ],
      ),
    );
  }
}
