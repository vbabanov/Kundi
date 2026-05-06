import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/schedule_repository_impl.dart';
import '../domain/schedule_entity.dart';

final scheduleControllerProvider =
    AsyncNotifierProvider<ScheduleController, List<ScheduleEntity>>(
  ScheduleController.new,
);

class ScheduleController extends AsyncNotifier<List<ScheduleEntity>> {
  final ScheduleRepositoryImpl _repository = ScheduleRepositoryImpl();

  @override
  Future<List<ScheduleEntity>> build() {
    return _repository.list();
  }
}
