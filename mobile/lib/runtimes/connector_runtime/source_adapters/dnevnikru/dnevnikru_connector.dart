import 'package:flutter/material.dart';

import '../../contracts/diary_connector.dart';
import '../../contracts/models.dart';

class DnevnikRuConnector implements DiaryConnector {
  @override
  Future<void> authenticate(DiaryAuthCredentials credentials) async {
    throw UnimplementedError('Dnevnik.ru connector is not implemented yet.');
  }

  @override
  Future<Map<String, String>> bootstrapSourceIds() async {
    throw UnimplementedError('Dnevnik.ru connector is not implemented yet.');
  }

  @override
  Future<SourceProfile> fetchProfile() async {
    throw UnimplementedError('Dnevnik.ru connector is not implemented yet.');
  }

  @override
  Future<List<SourceLesson>> fetchLessons(DateTimeRange window) async {
    throw UnimplementedError('Dnevnik.ru connector is not implemented yet.');
  }

  @override
  Future<List<SourceLesson>> fetchHomework(DateTimeRange window) async {
    throw UnimplementedError('Dnevnik.ru connector is not implemented yet.');
  }

  @override
  Future<List<SourceGrade>> fetchGrades(DateTimeRange weekWindow) async {
    throw UnimplementedError('Dnevnik.ru connector is not implemented yet.');
  }

  @override
  Future<CanonicalBundle> buildCanonicalBundle(
      DiarySyncRequest syncRequest) async {
    throw UnimplementedError('Dnevnik.ru connector is not implemented yet.');
  }
}
