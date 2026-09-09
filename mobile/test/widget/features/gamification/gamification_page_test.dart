import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/gamification/application/gamification_controller.dart';
import 'package:kundi_mobile/features/gamification/domain/gamification_entity.dart';
import 'package:kundi_mobile/features/gamification/presentation/gamification_page.dart';
import 'package:kundi_mobile/l10n/generated/app_localizations.dart';
import 'package:kundi_mobile/shared/theme/app_theme.dart';

void main() {
  for (final theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
    for (final locale in const <Locale>[Locale('ru'), Locale('kk')]) {
      testWidgets(
        'catalog renders unlocked and locked in ${theme.brightness} ${locale.languageCode}',
        (tester) async {
          final profile = _profile();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                gamificationControllerProvider.overrideWith(
                  () => _TestGamificationController(profile),
                ),
              ],
              child: MaterialApp(
                theme: theme,
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                home: GamificationPage(initialProfile: profile),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('gamification-catalog')), findsOneWidget);
          expect(find.byKey(const Key('gamification-summary')), findsOneWidget);
          expect(find.byKey(const Key('achievement-activity_first_day')),
              findsOneWidget);
          expect(find.byKey(const Key('achievement-activity_streak_3')),
              findsOneWidget);
          expect(
            find.text(
                locale.languageCode == 'kk' ? 'Алғашқы күн' : 'Первый день'),
            findsOneWidget,
          );
          expect(
            find.text(locale.languageCode == 'kk' ? 'Ырғақ' : 'Ритм'),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.workspace_premium_rounded), findsOneWidget);
          expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
        },
      );
    }
  }
}

class _TestGamificationController extends GamificationController {
  _TestGamificationController(this.profile);
  final GamificationProfile profile;

  @override
  Future<GamificationProfile?> build() async => profile;
}

GamificationProfile _profile() => GamificationProfile(
      catalogVersion: 1,
      points: 30,
      level: 1,
      levelFloorPoints: 0,
      nextLevelPoints: 100,
      currentStreak: 1,
      longestStreak: 1,
      lastActiveDate: DateTime.utc(2026, 9, 9),
      achievementsUnlocked: 1,
      achievementsTotal: 13,
      achievements: [
        AchievementEntity(
          code: 'activity_first_day',
          category: 'activity',
          categoryTitle: const LocalizedGamificationText(
              ru: 'Активность', kk: 'Белсенділік'),
          title: const LocalizedGamificationText(
              ru: 'Первый день', kk: 'Алғашқы күн'),
          description: const LocalizedGamificationText(
              ru: 'Впервые воспользуйся Kundi.',
              kk: 'Kundi қолданбасын алғаш рет пайдалан.'),
          current: 1,
          target: 1,
          unlocked: true,
          unlockedAt: DateTime.utc(2026, 9, 9),
          seen: true,
        ),
        const AchievementEntity(
          code: 'activity_streak_3',
          category: 'activity',
          categoryTitle:
              LocalizedGamificationText(ru: 'Активность', kk: 'Белсенділік'),
          title: LocalizedGamificationText(ru: 'Ритм', kk: 'Ырғақ'),
          description: LocalizedGamificationText(
              ru: 'Пользуйся Kundi 3 дня подряд.',
              kk: 'Kundi қолданбасын 3 күн қатарынан пайдалан.'),
          current: 1,
          target: 3,
          unlocked: false,
          unlockedAt: null,
          seen: false,
        ),
      ],
      pendingUnlocks: const <AchievementEntity>[],
    );
