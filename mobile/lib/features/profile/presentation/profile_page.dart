import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/kundi_tokens.dart';
import '../../../shared/widgets/kundi_surface.dart';
import '../application/profile_controller.dart';
import '../domain/profile_entity.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _phone1Controller = TextEditingController();
  final _phone2Controller = TextEditingController();
  int? _selectedShift;
  String _loadedKey = '';

  @override
  void dispose() {
    _phone1Controller.dispose();
    _phone2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: state.when(
        data: (profile) {
          if (profile == null) {
            return const KundiStateBody.empty(
              label: 'Профиль ещё не загружен',
              icon: Icons.person_search_outlined,
            );
          }
          _syncFormFromProfile(profile);
          final providerIdentity = profile.providerIdentity;
          return ListView(
            padding: const EdgeInsets.only(
              top: KundiSpace.xs,
              bottom: KundiSpace.md,
            ),
            children: [
              _SectionBlock(
                title: 'Данные ученика',
                child: providerIdentity == null
                    ? const _InlineStateText('Данные поставщика недоступны')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldRow(
                            label: 'Ученик',
                            value: _orNotSet(providerIdentity.studentFullName),
                          ),
                          _FieldRow(
                            label: 'Школа',
                            value: _orNotSet(providerIdentity.schoolName),
                          ),
                          _FieldRow(
                            label: 'Класс',
                            value: _orNotSet(providerIdentity.classLabel),
                          ),
                          _FieldRow(
                            label: 'Классный руководитель',
                            value: _orNotSet(
                                providerIdentity.classTeacherFullName),
                          ),
                        ],
                      ),
              ),
              _SectionBlock(
                title: 'Локальный профиль',
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _selectedShift,
                        decoration: const InputDecoration(
                          labelText: 'Смена',
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 смена')),
                          DropdownMenuItem(value: 2, child: Text('2 смена')),
                        ],
                        onChanged: (value) => setState(() {
                          _selectedShift = value;
                        }),
                        validator: (value) {
                          if (value == 1 || value == 2) {
                            return null;
                          }
                          return 'Выберите смену: 1 или 2';
                        },
                      ),
                      const SizedBox(height: KundiSpace.sm),
                      TextFormField(
                        controller: _phone1Controller,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Номер родителя 1',
                          hintText: '+7XXXXXXXXXX',
                        ),
                        validator: (value) {
                          final normalized = _normalizePhone(value ?? '');
                          if (normalized.isEmpty) {
                            return 'Введите номер родителя 1';
                          }
                          if (!_isValidPhone(normalized)) {
                            return 'Номер должен быть 10–15 цифр';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: KundiSpace.sm),
                      TextFormField(
                        controller: _phone2Controller,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Номер родителя 2 (опционально)',
                          hintText: '+7XXXXXXXXXX',
                        ),
                        validator: (value) {
                          final normalized = _normalizePhone(value ?? '');
                          if (normalized.isEmpty) {
                            return null;
                          }
                          if (!_isValidPhone(normalized)) {
                            return 'Номер должен быть 10–15 цифр';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: KundiSpace.md),
                      SizedBox(
                        width: double.infinity,
                        child: state.isLoading
                            ? FilledButton(
                                onPressed: null,
                                child: const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : KundiPrimaryButton(
                                label: 'Сохранить',
                                onPressed: _saveProfile,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const KundiStateBody.loading(),
        error: (error, _) => KundiStateBody.error(
          label: 'Не удалось загрузить профиль',
          onRetry: () =>
              ref.read(profileControllerProvider.notifier).refreshFromCache(),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedShift != 1 && _selectedShift != 2) {
      return;
    }
    final shift = _selectedShift!;

    final phone1 = _normalizePhone(_phone1Controller.text);
    final phone2 = _normalizePhone(_phone2Controller.text);

    await ref.read(profileControllerProvider.notifier).saveLocalAppProfile(
          shift: shift,
          parentPhone1: phone1,
          parentPhone2: phone2,
        );
    if (!mounted) {
      return;
    }
    final nextState = ref.read(profileControllerProvider);
    nextState.whenOrNull(
      error: (error, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $error')),
        );
      },
      data: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль сохранён')),
        );
      },
    );
  }

  void _syncFormFromProfile(ProfileEntity profile) {
    final local = profile.localAppProfile;
    final nextKey =
        '${profile.providerIdentity?.studentId}|${local?.shift}|${local?.parentPhone1}|${local?.parentPhone2}';
    if (_loadedKey == nextKey) {
      return;
    }
    _loadedKey = nextKey;
    _selectedShift = local?.shift;
    _phone1Controller.text = local?.parentPhone1 ?? '';
    _phone2Controller.text = local?.parentPhone2 ?? '';
  }

  String _normalizePhone(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      return '';
    }
    value = value
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('(', '')
        .replaceAll(')', '');
    final hasPlus = value.startsWith('+');
    value = value.replaceAll(RegExp(r'[^\d]'), '');
    if (value.isEmpty) {
      return '';
    }
    return hasPlus ? '+$value' : value;
  }

  bool _isValidPhone(String normalized) {
    final digits =
        normalized.startsWith('+') ? normalized.substring(1) : normalized;
    return digits.length >= 10 && digits.length <= 15;
  }
}

String _orNotSet(String raw) {
  final value = raw.trim();
  return value.isEmpty ? 'Не задано' : value;
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KundiSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KundiSectionHeader(title: title),
          const SizedBox(height: KundiSpace.xs),
          child,
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KundiSpace.xs),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _InlineStateText extends StatelessWidget {
  const _InlineStateText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
