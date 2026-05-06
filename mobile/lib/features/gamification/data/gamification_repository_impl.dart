import '../domain/gamification_entity.dart';
import '../domain/gamification_repository.dart';

class GamificationRepositoryImpl implements GamificationRepository {
  @override
  Future<List<GamificationEntity>> list() async {
    return const <GamificationEntity>[];
  }
}
