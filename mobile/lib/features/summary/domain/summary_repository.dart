import 'summary_entity.dart';

abstract class SummaryRepository {
  Future<SummaryEntity> get();
}
