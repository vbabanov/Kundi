import '../domain/attendance_entity.dart';
import '../domain/attendance_repository.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  @override
  Future<List<AttendanceEntity>> list() async {
    return const <AttendanceEntity>[];
  }
}
