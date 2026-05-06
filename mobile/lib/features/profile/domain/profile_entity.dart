class ProfileEntity {
  const ProfileEntity({
    required this.readMode,
    required this.providerIdentity,
    required this.localAppProfile,
  });

  final String readMode;
  final ProviderIdentityProfileSection? providerIdentity;
  final LocalAppProfileSection? localAppProfile;

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
