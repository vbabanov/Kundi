import '../contracts/models.dart';

class CanonicalBundleMapper {
  const CanonicalBundleMapper();

  CanonicalBundle map({
    required String source,
    required String account,
    required String idempotencyKey,
    required Map<String, String> sourceIds,
    required SourceProfile profile,
    required List<SourceLesson> lessons,
    required List<SourceAttendanceEvent> attendance,
    List<SourceAcademicResult> results = const <SourceAcademicResult>[],
    List<SourceAcademicAggregate> aggregates =
        const <SourceAcademicAggregate>[],
    List<SourceResultEvidence> evidence = const <SourceResultEvidence>[],
    SourceLocalAppProfile? localAppProfile,
  }) {
    return CanonicalBundle(
      source: source,
      sourceAccount: account,
      idempotencyKey: idempotencyKey,
      syncedAt: DateTime.now().toUtc(),
      sourceIds: sourceIds,
      profile: profile,
      lessons: lessons,
      attendance: attendance,
      results: results,
      aggregates: aggregates,
      evidence: evidence,
      localAppProfile: localAppProfile,
    );
  }
}
