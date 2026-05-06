import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository_impl.dart';
import '../domain/settings_entity.dart';

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, List<SettingsEntity>>(
  SettingsController.new,
);

class SettingsController extends AsyncNotifier<List<SettingsEntity>> {
  final SettingsRepositoryImpl _repository = SettingsRepositoryImpl();

  @override
  Future<List<SettingsEntity>> build() {
    return _repository.list();
  }
}
