import 'attendance_entity.dart';

abstract class AttendanceRepository {
  Future<List<AttendanceEntity>> list();
}
