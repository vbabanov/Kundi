import '../../../core/db/canonical_cache_store.dart';
import '../domain/homework_entity.dart';
import '../domain/homework_repository.dart';

class HomeworkRepositoryImpl implements HomeworkRepository {
  HomeworkRepositoryImpl(this._cacheStore);

  final CanonicalCacheStore _cacheStore;

  @override
  Future<List<HomeworkEntity>> list() async {
    final context = await _cacheStore.getActiveReadContext();
    if (context != null && context.hasCompleteV2Scope) {
      final lessonRows = await _cacheStore.listV2Lessons(context: context);
      final items = lessonRows
          .where((row) =>
              (row['homework_text'] ?? '').toString().trim().isNotEmpty)
          .map(
            (row) => HomeworkEntity(
              id: (row['lesson_id'] ?? '').toString(),
              description: (row['homework_text'] ?? '').toString(),
              requiresPhoto: false,
              lessonDate: (row['lesson_date'] ?? '').toString(),
              subjectName: (row['subject_name'] ?? '').toString(),
            ),
          )
          .toList(growable: false);
      items.sort((a, b) => b.lessonDate.compareTo(a.lessonDate));
      return items;
    }

    final rows = await _cacheStore.listHomework();
    return rows
        .map(
          (row) => HomeworkEntity(
            id: (row['homework_id'] ?? '').toString(),
            description: (row['description'] ?? '').toString(),
            requiresPhoto: ((row['requires_photo'] ?? 0).toString() == '1'),
            lessonDate: (row['lesson_date'] ?? '').toString(),
            subjectName: (row['subject_name'] ?? '').toString(),
          ),
        )
        .toList(growable: false);
  }
}
