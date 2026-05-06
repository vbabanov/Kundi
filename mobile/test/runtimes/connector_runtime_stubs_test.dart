import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kundi_mobile/runtimes/connector_runtime/contracts/models.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/source_adapters/dnevnikru/dnevnikru_connector.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/source_adapters/edupage/edupage_connector.dart';

void main() {
  test('dnevnik connector is explicit not-implemented stub', () async {
    final connector = DnevnikRuConnector();
    expect(
      () => connector.fetchLessons(
          DateTimeRange(start: DateTime(2026), end: DateTime(2026, 1, 2))),
      throwsA(isA<UnimplementedError>()),
    );
  });

  test('edupage connector is explicit not-implemented stub', () async {
    final connector = EduPageConnector();
    expect(
      () => connector.authenticate(
        const DiaryAuthCredentials(
            source: 'edupage', login: 'user', password: 'pass'),
      ),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
