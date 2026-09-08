import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../application/settings_controller.dart';
import '../domain/settings_entity.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: state.when(
        data: (settings) => ListView(
          children: [
            ListTile(
              title: Text(context.l10n.settingsTheme),
              trailing: DropdownButton<AppThemePreference>(
                value: settings.theme,
                items: [
                  DropdownMenuItem(
                    value: AppThemePreference.dark,
                    child: Text(context.l10n.settingsThemeDark),
                  ),
                  DropdownMenuItem(
                    value: AppThemePreference.light,
                    child: Text(context.l10n.settingsThemeLight),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setTheme(value);
                  }
                },
              ),
            ),
            ListTile(
              title: Text(context.l10n.settingsLanguage),
              trailing: DropdownButton<AppLanguage>(
                value: settings.language,
                items: [
                  DropdownMenuItem(
                    value: AppLanguage.ru,
                    child: Text(context.l10n.settingsLanguageRussian),
                  ),
                  DropdownMenuItem(
                    value: AppLanguage.kk,
                    child: Text(context.l10n.settingsLanguageKazakh),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setLanguage(value);
                  }
                },
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }
}
