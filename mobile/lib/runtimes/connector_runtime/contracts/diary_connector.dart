import 'package:flutter/material.dart';

import 'models.dart';

abstract class DiaryConnector {
  Future<void> authenticate(DiaryAuthCredentials credentials);

  Future<Map<String, String>> bootstrapSourceIds();

  Future<SourceProfile> fetchProfile();

  Future<List<SourceLesson>> fetchLessons(DateTimeRange window);

  Future<List<SourceLesson>> fetchHomework(DateTimeRange window);

  Future<List<SourceGrade>> fetchGrades(DateTimeRange weekWindow);

  Future<CanonicalBundle> buildCanonicalBundle(DiarySyncRequest syncRequest);
}
