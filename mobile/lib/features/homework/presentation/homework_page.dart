import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/kundi_tokens.dart';
import '../../../shared/widgets/kundi_surface.dart';
import '../../auth/application/auth_controller.dart';
import '../../homework/data/homework_day_whatsapp_repository.dart';
import '../../homework/data/homework_whatsapp_send_repository.dart';
import '../../lessons/application/lessons_controller.dart';
import '../../lessons/domain/lessons_entity.dart';
import '../../profile/application/profile_controller.dart';
import '../../profile/domain/profile_entity.dart';

enum _HomeworkMode { homework, topic }

enum _PhotoPreviewAction { send, retake, cancel }

enum _LessonSendStatus { idle, sending, sent, failed }

enum _FailureAction { retry, retake, cancel }

enum _SendFlowOutcome { sent, retakeRequired, cancelled }

const _unknownDayKey = '__unknown_day__';

final _homeworkWhatsAppSendRepositoryProvider =
    Provider<HomeworkWhatsappSendRepository>((ref) {
  return HomeworkWhatsappSendRepository(
      apiClient: ref.watch(apiClientProvider));
});

final _homeworkDayWhatsAppRepositoryProvider =
    Provider<HomeworkDayWhatsappRepository>((ref) {
  return HomeworkDayWhatsappRepository(apiClient: ref.watch(apiClientProvider));
});

class HomeworkPage extends ConsumerStatefulWidget {
  const HomeworkPage({super.key});

  @override
  ConsumerState<HomeworkPage> createState() => _HomeworkPageState();
}

class _HomeworkPageState extends ConsumerState<HomeworkPage>
    with AutomaticKeepAliveClientMixin<HomeworkPage> {
  _HomeworkMode _mode = _HomeworkMode.homework;
  String? _selectedDayKey;
  final ImagePicker _imagePicker = ImagePicker();
  final Map<String, _LessonSendStatus> _sendStatusByLesson =
      <String, _LessonSendStatus>{};

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lessonsState = ref.watch(lessonsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ДЗ / Тема')),
      body: lessonsState.when(
        data: (lessons) => _buildContent(context, lessons),
        loading: () => const KundiStateBody.loading(),
        error: (error, _) => KundiStateBody.error(
          label: 'Не удалось загрузить карточки уроков',
          onRetry: () =>
              ref.read(lessonsControllerProvider.notifier).refreshFromCache(),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<LessonsEntity> lessons) {
    if (lessons.isEmpty) {
      return const KundiStateBody.empty(label: 'Уроки пока не загружены');
    }

    final dayOptions = _collectDayOptions(lessons);
    final safeSelected = _ensureSelectedDay(dayOptions);
    final selectedLessons = lessons
        .where((lesson) => _dayKey(lesson.date) == safeSelected)
        .toList(growable: false)
      ..sort((a, b) {
        final lessonCompare = a.lessonNumber.compareTo(b.lessonNumber);
        if (lessonCompare != 0) return lessonCompare;
        final timeCompare = a.startTime.compareTo(b.startTime);
        if (timeCompare != 0) return timeCompare;
        return a.subjectName.compareTo(b.subjectName);
      });
    final selectedIndex =
        dayOptions.indexWhere((option) => option.dayKey == safeSelected);

    return Column(
      children: [
        const SizedBox(height: KundiSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
          child: _ModeToggle(
            mode: _mode,
            onModeChanged: (nextMode) {
              HapticFeedback.selectionClick();
              setState(() => _mode = nextMode);
            },
          ),
        ),
        const SizedBox(height: KundiSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
          child: _DaySwitch(
            label: dayOptions[selectedIndex].display,
            canGoBack: selectedIndex > 0,
            canGoForward: selectedIndex < dayOptions.length - 1,
            onBack: () {
              if (selectedIndex > 0) {
                setState(() =>
                    _selectedDayKey = dayOptions[selectedIndex - 1].dayKey);
              }
            },
            onForward: () {
              if (selectedIndex < dayOptions.length - 1) {
                setState(() =>
                    _selectedDayKey = dayOptions[selectedIndex + 1].dayKey);
              }
            },
          ),
        ),
        const SizedBox(height: KundiSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
          child: KundiSectionCard(
            margin: EdgeInsets.zero,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Сегодня ${selectedLessons.length} уроков',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
        const SizedBox(height: KundiSpace.xs),
        Expanded(
          child: selectedLessons.isEmpty
              ? const KundiStateBody.empty(
                  label: 'Сегодня уроков нет, отдыхайте!')
              : ListView.builder(
                  padding: const EdgeInsets.only(
                      top: KundiSpace.xs, bottom: KundiSpace.sm),
                  itemCount: selectedLessons.length,
                  itemBuilder: (context, index) {
                    final lesson = selectedLessons[index];
                    return _HomeworkLessonCard(
                      lesson: lesson,
                      mode: _mode,
                      isDanger: _isDangerLesson(lesson),
                      sendStatus: _sendStatusByLesson[lesson.id] ??
                          _LessonSendStatus.idle,
                      onLessonTap: () {
                        HapticFeedback.lightImpact();
                        _runManualPhotoWhatsAppFlow(lesson);
                      },
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              KundiSpace.sm, KundiSpace.xs, KundiSpace.sm, KundiSpace.sm),
          child: SizedBox(
            width: double.infinity,
            child: KundiWhatsAppButton(
              label: 'Отправить в WhatsApp',
              onPressed: () => _sendDayDigest(dayKey: safeSelected),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _sendDayDigest({required String dayKey}) async {
    if (dayKey == _unknownDayKey) {
      _showMessage('Для этого дня отправка недоступна: нет корректной даты.');
      return;
    }
    final authSession = ref.read(authControllerProvider).valueOrNull;
    if (authSession == null || authSession.accessToken.trim().isEmpty) {
      _showMessage('Сессия истекла. Выполните вход снова.');
      return;
    }
    final repository = ref.read(_homeworkDayWhatsAppRepositoryProvider);
    final mode = _mode == _HomeworkMode.homework
        ? HomeworkDayDigestMode.homework
        : HomeworkDayDigestMode.topic;
    try {
      final result = await repository.sendDayDigest(
        HomeworkDayWhatsappRequest(
          accessToken: authSession.accessToken,
          date: dayKey,
          mode: mode,
          idempotencyKey:
              'wh-day-${mode.apiValue}-$dayKey-${DateTime.now().toUtc().millisecondsSinceEpoch}',
        ),
      );
      if (!mounted) return;
      _showMessage(
        switch (result.status) {
          WhatsappDispatchStatus.sent =>
            'Сообщение за $dayKey отправлено в WhatsApp.',
          WhatsappDispatchStatus.queued =>
            'Отправка за $dayKey поставлена в очередь и ещё выполняется.',
          WhatsappDispatchStatus.failed => result.message.isEmpty
              ? 'Не удалось отправить сообщение за $dayKey.'
              : result.message,
        },
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(error is AppException
          ? error.message
          : 'Не удалось отправить сообщение в WhatsApp.');
    }
  }

  Future<void> _runManualPhotoWhatsAppFlow(LessonsEntity lesson) async {
    if ((_sendStatusByLesson[lesson.id] ?? _LessonSendStatus.idle) ==
        _LessonSendStatus.sending) return;

    final authSession = ref.read(authControllerProvider).valueOrNull;
    if (authSession == null || authSession.accessToken.trim().isEmpty) {
      _showMessage('Сессия истекла. Выполните вход снова.');
      return;
    }
    final profile = ref.read(profileControllerProvider).valueOrNull;
    final parentPhones = _collectParentPhones(profile?.localAppProfile);
    if (parentPhones.isEmpty) {
      _showMessage('Укажите номер родителя в профиле перед отправкой.');
      return;
    }

    String? photoPath = await _capturePhoto();
    while (photoPath != null) {
      final previewAction = await _openPreviewAndPickAction(
        lesson: lesson,
        mode: _mode,
        photoPath: photoPath,
      );
      if (!mounted) return;
      if (previewAction == _PhotoPreviewAction.cancel ||
          previewAction == null) {
        await _safeDeleteTemp(photoPath);
        return;
      }
      if (previewAction == _PhotoPreviewAction.retake) {
        await _safeDeleteTemp(photoPath);
        photoPath = await _capturePhoto();
        continue;
      }

      final sendOutcome = await _sendPhotoWithRetry(
        lesson: lesson,
        photoPath: photoPath,
        accessToken: authSession.accessToken,
        parentPhones: parentPhones,
      );
      if (!mounted) return;
      if (sendOutcome == _SendFlowOutcome.sent) {
        await _safeDeleteTemp(photoPath);
        setState(() => _sendStatusByLesson[lesson.id] = _LessonSendStatus.sent);
        HapticFeedback.lightImpact();
        _showMessage('Фото отправлено в WhatsApp.');
        return;
      }
      if (sendOutcome == _SendFlowOutcome.retakeRequired) {
        await _safeDeleteTemp(photoPath);
        photoPath = await _capturePhoto();
        continue;
      }

      await _safeDeleteTemp(photoPath);
      return;
    }
  }

  Future<_SendFlowOutcome> _sendPhotoWithRetry({
    required LessonsEntity lesson,
    required String photoPath,
    required String accessToken,
    required List<String> parentPhones,
  }) async {
    final repository = ref.read(_homeworkWhatsAppSendRepositoryProvider);
    final caption = _buildCaption(lesson);
    while (true) {
      final photoFile = File(photoPath);
      if (!await photoFile.exists()) {
        _showMessage('Файл фото недоступен. Снимите фото заново.');
        return _SendFlowOutcome.retakeRequired;
      }
      setState(
          () => _sendStatusByLesson[lesson.id] = _LessonSendStatus.sending);
      try {
        final sendResult = await repository.sendPhoto(
          HomeworkWhatsappSendRequest(
            accessToken: accessToken,
            homeworkId: lesson.id,
            filePath: photoPath,
            fileName: _buildFileName(lesson),
            caption: caption,
            parentPhones: parentPhones,
            idempotencyKey: _buildIdempotencyKey(lesson.id),
          ),
        );
        if (!sendResult.created &&
            sendResult.status == WhatsappDispatchStatus.queued) {
          _showMessage('Запрос уже был отправлен ранее, статус обновлён.');
        }
        if (sendResult.status == WhatsappDispatchStatus.sent) {
          return _SendFlowOutcome.sent;
        }
        _showMessage(sendResult.message);
        return _SendFlowOutcome.cancelled;
      } catch (error) {
        setState(
            () => _sendStatusByLesson[lesson.id] = _LessonSendStatus.failed);
        final retryAction = await _showSendFailureDialog(
          error is AppException ? error.message : 'Не удалось отправить фото.',
        );
        if (!mounted) return _SendFlowOutcome.cancelled;
        if (retryAction == _FailureAction.retry) continue;
        if (retryAction == _FailureAction.retake)
          return _SendFlowOutcome.retakeRequired;
        return _SendFlowOutcome.cancelled;
      }
    }
  }

  Future<XFile?> _pickFromCamera() {
    return _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 72,
      maxWidth: 1280,
      maxHeight: 1280,
      preferredCameraDevice: CameraDevice.rear,
    );
  }

  Future<String?> _capturePhoto() async {
    try {
      final photo = await _pickFromCamera();
      return photo?.path;
    } catch (_) {
      _showMessage('Камера недоступна. Проверьте разрешение приложения.');
      return null;
    }
  }

  Future<_PhotoPreviewAction?> _openPreviewAndPickAction({
    required LessonsEntity lesson,
    required _HomeworkMode mode,
    required String photoPath,
  }) {
    return Navigator.of(context).push<_PhotoPreviewAction>(
      MaterialPageRoute<_PhotoPreviewAction>(
        builder: (_) => _PhotoPreviewPage(
          lesson: lesson,
          mode: mode,
          photoPath: photoPath,
        ),
      ),
    );
  }

  Future<void> _safeDeleteTemp(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  String _buildFileName(LessonsEntity lesson) {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final nonce = const Uuid().v4().replaceAll('-', '').substring(0, 12);
    return 'hw_${timestamp}_$nonce.jpg';
  }

  String _buildCaption(LessonsEntity lesson) {
    final subject = lesson.subjectName.trim().isEmpty
        ? 'Предмет не указан'
        : lesson.subjectName.trim();
    final homework = lesson.homeworkText.trim().isEmpty
        ? 'не задано'
        : lesson.homeworkText.trim();
    final date = _dayKey(lesson.date) == _unknownDayKey
        ? lesson.date.trim()
        : _dayKey(lesson.date);
    return '*📚 $subject*\n$homework\n*📅 $date*';
  }

  String _buildIdempotencyKey(String lessonId) {
    final nonce = const Uuid().v4();
    return 'wh-photo-${lessonId.trim()}-$nonce';
  }

  List<String> _collectParentPhones(LocalAppProfileSection? localProfile) {
    if (localProfile == null) return const <String>[];
    final values = <String>[
      localProfile.parentPhone1.toString(),
      localProfile.parentPhone2.toString()
    ];
    final result = <String>[];
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isNotEmpty && !result.contains(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  Future<_FailureAction> _showSendFailureDialog(String message) async {
    final result = await showDialog<_FailureAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ошибка отправки'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(_FailureAction.cancel),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(_FailureAction.retake),
              child: const Text('Повторить фото')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(_FailureAction.retry),
              child: const Text('Повторить отправку')),
        ],
      ),
    );
    return result ?? _FailureAction.cancel;
  }

  void _showMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _ensureSelectedDay(List<_DayOption> options) {
    if (options.isEmpty) {
      _selectedDayKey = _unknownDayKey;
      return _unknownDayKey;
    }
    final keys = options.map((option) => option.dayKey).toSet();
    if (_selectedDayKey != null && keys.contains(_selectedDayKey)) {
      return _selectedDayKey!;
    }
    final today = DateTime.now();
    final todayKey =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    if (keys.contains(todayKey)) {
      _selectedDayKey = todayKey;
      return todayKey;
    }
    _selectedDayKey = options.first.dayKey;
    return _selectedDayKey!;
  }

  List<_DayOption> _collectDayOptions(List<LessonsEntity> lessons) {
    final grouped = <String, String>{};
    for (final lesson in lessons) {
      final key = _dayKey(lesson.date);
      grouped.putIfAbsent(key, () => _formatDayLabel(key));
    }
    final options = grouped.entries
        .map((entry) => _DayOption(dayKey: entry.key, display: entry.value))
        .toList(growable: false)
      ..sort((a, b) => a.dayKey.compareTo(b.dayKey));
    return options;
  }

  bool _isDangerLesson(LessonsEntity lesson) {
    final normalized = _normalizeDangerText(
        [lesson.subjectName, lesson.topic, lesson.homeworkText].join(' '));
    if (normalized.isEmpty) return false;
    final tokens =
        normalized.split(RegExp(r'\s+')).where((token) => token.isNotEmpty);
    return tokens.any((token) =>
        token == 'сор' ||
        token == 'соч' ||
        token == 'sor' ||
        token == 'soch' ||
        token.startsWith('контрольн'));
  }

  String _dayKey(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.length >= 10 && trimmed[4] == '-' && trimmed[7] == '-') {
      return trimmed.substring(0, 10);
    }
    return _unknownDayKey;
  }

  String _formatDayLabel(String dayKey) {
    if (dayKey == _unknownDayKey) return 'Без даты';
    final parsed = DateTime.tryParse(dayKey);
    if (parsed == null) return dayKey;

    const weekdays = <int, String>{
      DateTime.monday: 'Пн',
      DateTime.tuesday: 'Вт',
      DateTime.wednesday: 'Ср',
      DateTime.thursday: 'Чт',
      DateTime.friday: 'Пт',
      DateTime.saturday: 'Сб',
      DateTime.sunday: 'Вс',
    };
    const months = <int, String>{
      1: 'янв',
      2: 'фев',
      3: 'мар',
      4: 'апр',
      5: 'май',
      6: 'июн',
      7: 'июл',
      8: 'авг',
      9: 'сен',
      10: 'окт',
      11: 'ноя',
      12: 'дек',
    };
    final weekday = weekdays[parsed.weekday] ?? '';
    final month = months[parsed.month] ?? '';
    return '$weekday, ${parsed.day} $month';
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onModeChanged});

  final _HomeworkMode mode;
  final ValueChanged<_HomeworkMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.kundiElevated.withValues(alpha: 0.72),
          borderRadius: KundiRadius.pill,
          border: Border.all(color: scheme.kundiBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModePill(
              label: 'ДЗ',
              icon: Icons.check_rounded,
              selected: mode == _HomeworkMode.homework,
              onTap: () => onModeChanged(_HomeworkMode.homework),
            ),
            const SizedBox(width: 6),
            _ModePill(
              label: 'Тема',
              icon: Icons.menu_book_rounded,
              selected: mode == _HomeworkMode.topic,
              onTap: () => onModeChanged(_HomeworkMode.topic),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySwitch extends StatelessWidget {
  const _DaySwitch({
    required this.label,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  final String label;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KundiSectionCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _EarButton(
              icon: Icons.chevron_left, enabled: canGoBack, onPressed: onBack),
          Expanded(
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
              ),
            ),
          ),
          _EarButton(
              icon: Icons.chevron_right,
              enabled: canGoForward,
              onPressed: onForward),
        ],
      ),
    );
  }
}

class _EarButton extends StatelessWidget {
  const _EarButton(
      {required this.icon, required this.enabled, required this.onPressed});

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: KundiRadius.pill,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: KundiRadius.pill,
          color: selected
              ? scheme.primary.withValues(alpha: 0.30)
              : Colors.transparent,
          border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.65)
                  : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.kundiTextSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.kundiTextSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeworkLessonCard extends StatelessWidget {
  const _HomeworkLessonCard({
    required this.lesson,
    required this.mode,
    required this.isDanger,
    required this.sendStatus,
    required this.onLessonTap,
  });

  final LessonsEntity lesson;
  final _HomeworkMode mode;
  final bool isDanger;
  final _LessonSendStatus sendStatus;
  final VoidCallback onLessonTap;

  @override
  Widget build(BuildContext context) {
    final subject = lesson.subjectName.trim().isEmpty
        ? 'Без предмета'
        : lesson.subjectName.trim();
    final content = mode == _HomeworkMode.homework
        ? lesson.homeworkText.trim()
        : lesson.topic.trim();
    final timeRange =
        (lesson.startTime.trim().isNotEmpty && lesson.endTime.trim().isNotEmpty)
            ? '${lesson.startTime.trim()}-${lesson.endTime.trim()}'
            : '';
    final headerLine =
        'Урок ${lesson.lessonNumber} · $subject${timeRange.isEmpty ? '' : ' · $timeRange'}';

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KundiSpace.sm, vertical: KundiSpace.xs),
      child: InkWell(
        borderRadius: KundiRadius.md,
        onTap: sendStatus == _LessonSendStatus.sending ? null : onLessonTap,
        child: KundiAttentionPulse(
          active: isDanger,
          child: KundiSectionCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(
                horizontal: KundiSpace.sm, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: KundiSpace.xs),
                      Text(
                        content.isNotEmpty
                            ? content
                            : mode == _HomeworkMode.homework
                                ? 'Домашнее задание не задано'
                                : 'Тема урока не указана',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: KundiSpace.xs),
                _StatusSlot(danger: isDanger, sendStatus: sendStatus),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusSlot extends StatelessWidget {
  const _StatusSlot({required this.danger, required this.sendStatus});

  final bool danger;
  final _LessonSendStatus sendStatus;

  @override
  Widget build(BuildContext context) {
    final badgeColor = Theme.of(context).colorScheme.error;
    final successColor = Colors.green.shade400;
    const pendingColor = Color(0xFF8E82A8);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (danger)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: KundiSpace.xs, vertical: KundiSpace.xxs),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: badgeColor.withValues(alpha: 0.55)),
            ),
            child: Text(
              'Контроль',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: badgeColor, fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(height: KundiSpace.xs),
        if (sendStatus == _LessonSendStatus.sent)
          Icon(Icons.check_circle, color: successColor, size: 30)
        else if (sendStatus == _LessonSendStatus.sending)
          const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2))
        else
          const Icon(Icons.radio_button_unchecked_rounded,
              color: pendingColor, size: 30),
      ],
    );
  }
}

class _PhotoPreviewPage extends StatelessWidget {
  const _PhotoPreviewPage(
      {required this.lesson, required this.mode, required this.photoPath});

  final LessonsEntity lesson;
  final _HomeworkMode mode;
  final String photoPath;

  @override
  Widget build(BuildContext context) {
    final content = mode == _HomeworkMode.homework
        ? lesson.homeworkText.trim()
        : lesson.topic.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Предпросмотр фото')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(KundiSpace.sm),
                child: ClipRRect(
                  borderRadius: KundiRadius.md,
                  child: Image.file(File(photoPath),
                      width: double.infinity, fit: BoxFit.contain),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
              child: KundiSectionCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Предмет: ${lesson.subjectName.trim().isEmpty ? 'Не указан' : lesson.subjectName.trim()}'),
                    const SizedBox(height: KundiSpace.xxs),
                    Text(
                        '${mode == _HomeworkMode.homework ? 'Задание' : 'Тема'}: ${content.isEmpty ? 'Не указано' : content}'),
                    const SizedBox(height: KundiSpace.xxs),
                    Text(
                        'Дата: ${lesson.date.trim().isEmpty ? 'Не указана' : lesson.date.trim()}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: KundiSpace.sm),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KundiSpace.sm, 0, KundiSpace.sm, KundiSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_PhotoPreviewAction.cancel),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: KundiSpace.xs),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_PhotoPreviewAction.retake),
                      child: const Text('Повторить'),
                    ),
                  ),
                  const SizedBox(width: KundiSpace.xs),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_PhotoPreviewAction.send),
                      child: const Text('Отправить'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayOption {
  const _DayOption({required this.dayKey, required this.display});

  final String dayKey;
  final String display;
}

String _normalizeDangerText(String value) {
  final lowered = value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll('cор', 'сор')
      .replaceAll('cоч', 'соч');
  return lowered
      .replaceAll(RegExp(r'[^a-zа-я0-9]+', unicode: true), ' ')
      .trim();
}
