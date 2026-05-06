import 'grades_entity.dart';

abstract class GradesRepository {
  Future<GradesScreenData> get();
}
