import 'homework_entity.dart';

abstract class HomeworkRepository {
  Future<List<HomeworkEntity>> list();
}
