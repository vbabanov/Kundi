import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/gamification/domain/gamification_entity.dart';
import 'package:kundi_mobile/features/gamification/presentation/achievement_progress.dart';

void main() {
  test('display progress clamps current without changing domain metric', () {
    const achievement = AchievementEntity(
      code: 'test',
      category: 'test',
      categoryTitle: LocalizedGamificationText(ru: 'Тест', kk: 'Тест'),
      title: LocalizedGamificationText(ru: 'Тест', kk: 'Тест'),
      description: LocalizedGamificationText(ru: 'Тест', kk: 'Тест'),
      current: 120,
      target: 100,
      unlocked: true,
      unlockedAt: null,
      seen: true,
    );

    expect(displayAchievementCurrent(achievement), 100);
    expect(achievement.current, 120);
  });
}
