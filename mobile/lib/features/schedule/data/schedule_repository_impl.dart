import '../domain/schedule_entity.dart';
import '../domain/schedule_repository.dart';

class ScheduleRepositoryImpl implements ScheduleRepository {
  @override
  Future<List<ScheduleEntity>> list() async {
    return const <ScheduleEntity>[];
  }
}
