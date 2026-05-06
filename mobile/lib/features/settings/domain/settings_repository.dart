import 'settings_entity.dart';

abstract class SettingsRepository {
  Future<List<SettingsEntity>> list();
}
