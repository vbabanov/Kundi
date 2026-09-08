import 'profile_entity.dart';

abstract class ProfileRepository {
  Future<ProfileEntity?> get();

  Future<void> saveLocalAppProfile({
    required String parentPhone1,
    required String parentPhone2,
  });
}
