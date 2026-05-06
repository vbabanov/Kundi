import 'lessons_entity.dart';

abstract class LessonsRepository {
  Future<List<LessonsEntity>> list();
}
