import 'school_shift.dart';

class ProfileEntity {
  const ProfileEntity({
    required this.readMode,
    required this.providerIdentity,
    required this.localAppProfile,
    this.automaticShift = SchoolShift.unknown,
  });

  final String readMode;
  final ProviderIdentityProfileSection? providerIdentity;
  final LocalAppProfileSection? localAppProfile;
  final SchoolShift automaticShift;

  bool get hasData => providerIdentity != null || localAppProfile != null;
}

class ProviderIdentityProfileSection {
  const ProviderIdentityProfileSection({
    required this.studentId,
    required this.provider,
    required this.providerAccountRef,
    required this.providerPersonId,
    required this.providerSchoolId,
    required this.providerGroupId,
    required this.studentFullName,
    required this.schoolName,
    required this.classLabel,
    required this.classTeacherFullName,
    required this.gradeLevel,
    this.studentFirstName = '',
  });

  final String studentId;
  final String provider;
  final String providerAccountRef;
  final String providerPersonId;
  final String providerSchoolId;
  final String providerGroupId;
  final String studentFullName;
  final String schoolName;
  final String classLabel;
  final String classTeacherFullName;
  final int gradeLevel;
  final String studentFirstName;
}

class LocalAppProfileSection {
  const LocalAppProfileSection({
    required this.shift,
    required this.parentPhone1,
    required this.parentPhone2,
  });

  final int? shift;
  final String parentPhone1;
  final String parentPhone2;
}

String resolveStudentFirstName({
  required String explicitFirstName,
  required String fullName,
}) {
  final explicit = explicitFirstName.trim();
  if (explicit.isNotEmpty) {
    return explicit.split(RegExp(r'\s+')).first;
  }

  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length < 2) {
    return parts.isEmpty ? '' : parts.first;
  }
  return _looksLikeSurname(parts.first) ? parts[1] : parts.first;
}

bool _looksLikeSurname(String value) {
  final normalized = value.toLowerCase();
  return RegExp(
    r'(ов|ев|ёв|ин|ын|ский|цкий|ская|цкая|енко|ук|юк|ко|дзе|ян|янц)$',
  ).hasMatch(normalized);
}
