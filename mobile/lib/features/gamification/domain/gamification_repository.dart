import 'gamification_entity.dart';

abstract class GamificationRepository {
  Future<List<GamificationEntity>> list();
}
