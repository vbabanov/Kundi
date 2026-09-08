import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/profile/application/profile_controller.dart';
import 'package:kundi_mobile/features/profile/domain/profile_entity.dart';
import 'package:kundi_mobile/features/profile/domain/profile_repository.dart';
import 'package:kundi_mobile/features/profile/domain/school_shift.dart';
import 'package:kundi_mobile/features/profile/presentation/profile_page.dart';
import 'package:kundi_mobile/features/settings/domain/settings_entity.dart';
import 'package:kundi_mobile/shared/theme/app_theme.dart';

void main() {
  testWidgets('renders profile hero, student data and parent contacts',
      (tester) async {
    final repository = _FakeProfileRepository([
      _profileEntityWithLocal(),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Artem Bayurzan'), findsWidgets);
    expect(find.text('Данные ученика'), findsOneWidget);
    expect(find.text('Класс'), findsWidgets);
    expect(find.textContaining('School 1'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Сохранить изменения'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Контакты'), findsOneWidget);
    expect(find.text('1 смена'), findsWidgets);
    expect(find.text('Номер родителя 1'), findsOneWidget);
    expect(find.textContaining('Номер родителя 2'), findsOneWidget);
    expect(find.text('Сохранить изменения'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.text('Настройки'), findsOneWidget);
  });

  testWidgets('renders profile screen with empty local contacts safely',
      (tester) async {
    final repository = _FakeProfileRepository([
      _profileEntityProviderOnly(),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Provider Only'), findsWidgets);
    expect(find.text('Данные ученика'), findsOneWidget);
    expect(find.byKey(const Key('profile-automatic-shift')), findsOneWidget);
    expect(find.text('—'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Сохранить изменения'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Контакты'), findsOneWidget);
    expect(find.text('Номер родителя 1'), findsOneWidget);
    expect(find.text('Сохранить изменения'), findsOneWidget);
  });

  testWidgets('key russian labels are not mojibake', (tester) async {
    final repository = _FakeProfileRepository([
      _profileEntityWithLocal(),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Данные ученика'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Сохранить изменения'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final broken in ['Рђ', 'Рџ', 'Ð', 'Ñ', 'вЂ']) {
      expect(find.textContaining(broken), findsNothing);
    }

    expect(find.textContaining('Контакты'), findsOneWidget);
    expect(find.text('Сохранить изменения'), findsOneWidget);
  });

  testWidgets('light theme keeps page chrome and dark settings card readable',
      (tester) async {
    final repository = _FakeProfileRepository([
      _profileEntityWithLocal(),
    ]);
    final theme = AppTheme.light;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(theme: theme, home: const ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('Профиль')).style?.color,
      theme.colorScheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('Данные ученика')).style?.color,
      theme.colorScheme.onSurface,
    );

    await tester.scrollUntilVisible(
      find.text('Тема'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text('Тема')).style?.color, Colors.white);
    final themeDropdown = tester.widget<DropdownButton<AppThemePreference>>(
      find.byType(DropdownButton<AppThemePreference>),
    );
    expect(themeDropdown.style?.color, Colors.white);
  });
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this._responses);

  final List<ProfileEntity?> _responses;
  int _index = 0;

  @override
  Future<ProfileEntity?> get() async {
    if (_responses.isEmpty) {
      return null;
    }
    final current =
        _index < _responses.length ? _responses[_index] : _responses.last;
    _index += 1;
    return current;
  }

  @override
  Future<void> saveLocalAppProfile({
    required String parentPhone1,
    required String parentPhone2,
  }) async {}
}

ProfileEntity _profileEntityWithLocal() {
  return const ProfileEntity(
    readMode: 'v2',
    automaticShift: SchoolShift.first,
    providerIdentity: ProviderIdentityProfileSection(
      studentId: 'student-1',
      provider: 'kundelik',
      providerAccountRef: 'acc-1',
      providerPersonId: 'person-1',
      providerSchoolId: 'school-1',
      providerGroupId: 'group-1',
      studentFullName: 'Artem Bayurzan',
      schoolName: 'School 1',
      classLabel: '7Zh',
      classTeacherFullName: 'Teacher Name',
      gradeLevel: 7,
    ),
    localAppProfile: LocalAppProfileSection(
      shift: 1,
      parentPhone1: '+77010000001',
      parentPhone2: '+77010000002',
    ),
  );
}

ProfileEntity _profileEntityProviderOnly() {
  return const ProfileEntity(
    readMode: 'v2',
    providerIdentity: ProviderIdentityProfileSection(
      studentId: 'student-1',
      provider: 'kundelik',
      providerAccountRef: 'acc-1',
      providerPersonId: 'person-1',
      providerSchoolId: 'school-1',
      providerGroupId: 'group-1',
      studentFullName: 'Provider Only',
      schoolName: 'School 1',
      classLabel: '7Zh',
      classTeacherFullName: 'Teacher Name',
      gradeLevel: 7,
    ),
    localAppProfile: null,
  );
}
