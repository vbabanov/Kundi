import 'gamification_entity.dart';

abstract class GamificationRepository {
  Future<GamificationProfile> getProfile();

  Future<GamificationProfile> recordActivity();

  Future<void> acknowledge(List<String> achievementCodes);
}
