import 'dart:math' as math;

import '../domain/gamification_entity.dart';

int displayAchievementCurrent(AchievementEntity achievement) {
  return math.min(achievement.current, achievement.target);
}
