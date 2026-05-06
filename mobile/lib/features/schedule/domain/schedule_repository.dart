import 'schedule_entity.dart';

abstract class ScheduleRepository {
  Future<List<ScheduleEntity>> list();
}
