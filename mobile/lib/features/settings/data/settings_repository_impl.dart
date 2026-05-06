import '../domain/settings_entity.dart';
import '../domain/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  @override
  Future<List<SettingsEntity>> list() async {
    return const <SettingsEntity>[];
  }
}
