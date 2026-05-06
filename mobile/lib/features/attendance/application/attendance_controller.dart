import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attendance_repository_impl.dart';
import '../domain/attendance_entity.dart';

final attendanceControllerProvider =
    AsyncNotifierProvider<AttendanceController, List<AttendanceEntity>>(
  AttendanceController.new,
);

class AttendanceController extends AsyncNotifier<List<AttendanceEntity>> {
  final AttendanceRepositoryImpl _repository = AttendanceRepositoryImpl();

  @override
  Future<List<AttendanceEntity>> build() {
    return _repository.list();
  }
}
