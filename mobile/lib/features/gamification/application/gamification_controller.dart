import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gamification_repository_impl.dart';
import '../domain/gamification_entity.dart';

final gamificationControllerProvider =
    AsyncNotifierProvider<GamificationController, List<GamificationEntity>>(
  GamificationController.new,
);

class GamificationController extends AsyncNotifier<List<GamificationEntity>> {
  final GamificationRepositoryImpl _repository = GamificationRepositoryImpl();

  @override
  Future<List<GamificationEntity>> build() {
    return _repository.list();
  }
}
