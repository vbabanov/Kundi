import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/kundi_tokens.dart';
import '../../../shared/widgets/kundi_surface.dart';
import '../../../shared/widgets/student_pull_to_refresh.dart';
import '../../auth/application/auth_controller.dart';
import '../../homework/data/homework_day_whatsapp_repository.dart';
import '../../homework/data/homework_whatsapp_send_repository.dart';
import '../../homework/domain/homework_progress.dart';
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
      body: lessonsState.when(
        data: (lessons) => RefreshIndicator(
          notificationPredicate: studentRefreshNotification,
          onRefresh: () => refreshStudentFromGesture(context, ref),
          child: SafeArea(
            bottom: false,
            child: _buildContent(context, lessons),
          ),
        ),
        loading: () => const KundiStateBody.loading(),
        error: (error, _) => KundiStateBody.error(
          label: context.l10n.homeworkLoadFailed,
          onRetry: () =>
              ref.read(lessonsControllerProvider.notifier).refreshFromCache(),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<LessonsEntity> lessons) {
    final lessonDayKeys = _collectLessonDayKeys(lessons);
    final safeSelectedDay = _ensureSelectedDay(lessonDayKeys);
    final selectedDate = _parseDayKey(safeSelectedDay) ?? DateTime.now();
    final weekStart = _startOfWeek(selectedDate);
    final weekDates = List<DateTime>.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
      growable: false,
    );

    final selectedLessons = lessons
        .where((lesson) => _dayKey(lesson.date) == safeSelectedDay)
        .toList(growable: false)
      ..sort((a, b) {
        final lessonCompare = a.lessonNumber.compareTo(b.lessonNumber);
        if (lessonCompare != 0) return lessonCompare;
        final timeCompare = a.startTime.compareTo(b.startTime);
        if (timeCompare != 0) return timeCompare;
        return a.subjectName.compareTo(b.subjectName);
      });
    final completedPrefixCount = _completedPrefixCount(selectedLessons);

    final doneCount = selectedLessons.where(_isLessonCompleted).length;
    final lessonsCount = selectedLessons.length;
    final progressPercent =
        lessonsCount == 0 ? null : ((doneCount / lessonsCount) * 100).round();

    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: _HomeworkTopDecor(),
          ),
        ),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
              child: Row(
                children: [
                  _HeaderIconButton(
                    icon: Icons.menu_rounded,
                    onTap: () {},
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        context.l10n.navHomework,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  _HeaderIconButton(
                    icon: Icons.search_rounded,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _HomeworkWeekdaySelector(
                weekDates: weekDates,
                selectedDayKey: safeSelectedDay,
                onBack: () => setState(() {
                  _selectedDayKey =
                      _toDayKey(selectedDate.subtract(const Duration(days: 7)));
                }),
                onForward: () => setState(() {
                  _selectedDayKey =
                      _toDayKey(selectedDate.add(const Duration(days: 7)));
                }),
                onSelectDay: (dayKey) =>
                    setState(() => _selectedDayKey = dayKey),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _HomeworkSummaryCard(
                lessonsCount: lessonsCount,
                doneCount: doneCount,
                progressPercent: progressPercent,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _HomeworkModeToggle(
                mode: _mode,
                onModeChanged: (nextMode) {
                  HapticFeedback.selectionClick();
                  setState(() => _mode = nextMode);
                },
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: KeyedSubtree(
                key: const Key('homework-pull-scroll'),
                child: selectedLessons.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        children: const [_HomeworkEmptyDayCard()],
                      )
                    : ListView.separated(
                        key: const Key('homework-lessons-list'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                        itemCount: selectedLessons.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final lesson = selectedLessons[index];
                          return _HomeworkLessonCard(
                            lesson: lesson,
                            mode: _mode,
                            isDone: _isLessonCompleted(lesson),
                            progressActive: index < completedPrefixCount,
                            sendStatus: _sendStatusByLesson[lesson.id] ??
                                _LessonSendStatus.idle,
                            isFirst: index == 0,
                            isLast: index == selectedLessons.length - 1,
                            onLessonTap: () {
                              HapticFeedback.lightImpact();
                              _runManualPhotoWhatsAppFlow(lesson);
                            },
                          );
                        },
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
              child: SizedBox(
                width: double.infinity,
                child: _HomeworkWhatsAppButton(
                  label: context.l10n.homeworkSendToday,
                  onPressed: () => _sendDayDigest(dayKey: safeSelectedDay),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isLessonCompleted(LessonsEntity lesson) {
    final status = _sendStatusByLesson[lesson.id];
    if (status == _LessonSendStatus.sent) return true;
    if (status == _LessonSendStatus.sending ||
        status == _LessonSendStatus.failed) {
      return false;
    }
    return isHomeworkCompleted(lesson);
  }

  int _completedPrefixCount(List<LessonsEntity> lessons) {
    var count = 0;
    for (final lesson in lessons) {
      if (_isLessonCompleted(lesson)) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  Set<String> _collectLessonDayKeys(List<LessonsEntity> lessons) {
    final result = <String>{};
    for (final lesson in lessons) {
      final key = _dayKey(lesson.date);
      if (key != _unknownDayKey) result.add(key);
    }
    return result;
  }

  DateTime _startOfWeek(DateTime day) {
    final base = DateTime(day.year, day.month, day.day);
    return base.subtract(Duration(days: base.weekday - DateTime.monday));
  }

  String _ensureSelectedDay(Set<String> dayKeys) {
    if (_selectedDayKey != null && _selectedDayKey != _unknownDayKey) {
      return _selectedDayKey!;
    }
    final todayKey = _toDayKey(DateTime.now());
    if (dayKeys.contains(todayKey)) {
      _selectedDayKey = todayKey;
      return todayKey;
    }
    if (dayKeys.isNotEmpty) {
      final sorted = dayKeys.toList()..sort();
      _selectedDayKey = sorted.first;
      return _selectedDayKey!;
    }
    _selectedDayKey = todayKey;
    return todayKey;
  }

  String _toDayKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDayKey(String value) {
    if (value == _unknownDayKey) return null;
    return DateTime.tryParse(value);
  }

  String _dayKey(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.length >= 10 && trimmed[4] == '-' && trimmed[7] == '-') {
      return trimmed.substring(0, 10);
    }
    return _unknownDayKey;
  }

  Future<void> _sendDayDigest({required String dayKey}) async {
    if (dayKey == _unknownDayKey) {
      _showMessage(context.l10n.homeworkInvalidDate);
      return;
    }
    final authSession = ref.read(authControllerProvider).valueOrNull;
    if (authSession == null || authSession.accessToken.trim().isEmpty) {
      _showMessage(context.l10n.homeworkSessionExpired);
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
            context.l10n.homeworkDigestSent(dayKey),
          WhatsappDispatchStatus.queued =>
            context.l10n.homeworkDigestQueued(dayKey),
          WhatsappDispatchStatus.failed => result.message.isEmpty
              ? context.l10n.homeworkDigestDateFailed(dayKey)
              : result.message,
        },
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(error is AppException
          ? error.message
          : context.l10n.homeworkWhatsappFailed);
    }
  }

  Future<void> _runManualPhotoWhatsAppFlow(LessonsEntity lesson) async {
    if ((_sendStatusByLesson[lesson.id] ?? _LessonSendStatus.idle) ==
        _LessonSendStatus.sending) return;

    final authSession = ref.read(authControllerProvider).valueOrNull;
    if (authSession == null || authSession.accessToken.trim().isEmpty) {
      _showMessage(context.l10n.homeworkSessionExpired);
      return;
    }
    final profile = ref.read(profileControllerProvider).valueOrNull;
    final parentPhones = _collectParentPhones(profile?.localAppProfile);
    if (parentPhones.isEmpty) {
      _showMessage(context.l10n.homeworkParentPhoneRequired);
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
        _showMessage(context.l10n.homeworkPhotoSent);
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
        _showMessage(context.l10n.homeworkPhotoMissing);
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
          _showMessage(context.l10n.homeworkAlreadySent);
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
          error is AppException
              ? error.message
              : context.l10n.homeworkPhotoSendFailed,
        );
        if (!mounted) return _SendFlowOutcome.cancelled;
        if (retryAction == _FailureAction.retry) continue;
        if (retryAction == _FailureAction.retake) {
          return _SendFlowOutcome.retakeRequired;
        }
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
      _showMessage(context.l10n.homeworkCameraUnavailable);
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
        ? context.l10n.homeworkSubjectMissing
        : lesson.subjectName.trim();
    final homework = lesson.homeworkText.trim().isEmpty
        ? context.l10n.homeworkNotAssigned
        : lesson.homeworkText.trim();
    final date = _dayKey(lesson.date) == _unknownDayKey
        ? lesson.date.trim()
        : _dayKey(lesson.date);
    return '📚 $subject\n$homework\n📅 $date';
  }

  String _buildIdempotencyKey(String lessonId) {
    final nonce = const Uuid().v4();
    return 'wh-photo-${lessonId.trim()}-$nonce';
  }

  List<String> _collectParentPhones(LocalAppProfileSection? localProfile) {
    if (localProfile == null) return const <String>[];
    final values = <String>[
      localProfile.parentPhone1.toString(),
      localProfile.parentPhone2.toString(),
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
        title: Text(context.l10n.homeworkSendError),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(_FailureAction.cancel),
              child: Text(context.l10n.commonCancel)),
          TextButton(
              onPressed: () => Navigator.of(context).pop(_FailureAction.retake),
              child: Text(context.l10n.homeworkRetakePhoto)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(_FailureAction.retry),
              child: Text(context.l10n.homeworkRetrySend)),
        ],
      ),
    );
    return result ?? _FailureAction.cancel;
  }

  void _showMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: isDark
              ? const Color(0x4A130E30)
              : scheme.surface.withValues(alpha: 0.92),
          border: Border.all(
            color: isDark
                ? const Color(0x70302466)
                : scheme.primary.withValues(alpha: 0.45),
          ),
        ),
        child: Icon(
          icon,
          color: isDark ? const Color(0xFFE6DBFF) : scheme.onSurface,
          size: 23,
        ),
      ),
    );
  }
}

class _HomeworkTopDecor extends StatelessWidget {
  const _HomeworkTopDecor();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -130,
          left: -40,
          right: -40,
          child: Container(
            height: 320,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.4),
                radius: 0.95,
                colors: [
                  Color(0x34196BFF),
                  Color(0x160D3CC0),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        for (final star in const <Offset>[
          Offset(56, 72),
          Offset(188, 58),
          Offset(280, 86),
          Offset(318, 132),
          Offset(214, 152),
        ])
          Positioned(
            left: star.dx,
            top: star.dy,
            child: Container(
              width: 3.2,
              height: 3.2,
              decoration: const BoxDecoration(
                color: Color(0x88B98AFF),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _WeekArrow extends StatelessWidget {
  const _WeekArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0x291A103D),
          border: Border.all(color: const Color(0x57352362)),
        ),
        child: Icon(icon, color: const Color(0xFFD9CDFD), size: 20),
      ),
    );
  }
}

class _HomeworkWeekdaySelector extends StatelessWidget {
  const _HomeworkWeekdaySelector({
    required this.weekDates,
    required this.selectedDayKey,
    required this.onBack,
    required this.onForward,
    required this.onSelectDay,
  });

  final List<DateTime> weekDates;
  final String selectedDayKey;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final ValueChanged<String> onSelectDay;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('homework-week-day-selector'),
      height: 82,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF120D2C), Color(0xFF1A1338)],
        ),
        border: Border.all(color: const Color(0x6F3A2A69)),
      ),
      child: Row(
        children: [
          _WeekArrow(icon: Icons.chevron_left_rounded, onTap: onBack),
          const SizedBox(width: 5),
          for (final date in weekDates)
            Expanded(
              child: _WeekdayChip(
                date: date,
                selected:
                    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' ==
                        selectedDayKey,
                onTap: () => onSelectDay(
                  '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
          const SizedBox(width: 5),
          _WeekArrow(icon: Icons.chevron_right_rounded, onTap: onForward),
        ],
      ),
    );
  }
}

class _WeekdayChip extends StatelessWidget {
  const _WeekdayChip({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isWeekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        key: Key(
            'homework-weekday-chip-${date.weekday}-${selected ? 'on' : 'off'}'),
        duration: const Duration(milliseconds: 170),
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? const Color(0x5A4D2FA0) : Colors.transparent,
          border: Border.all(
            color: selected ? const Color(0xA78E62FF) : Colors.transparent,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x4A8E56FF),
                    blurRadius: 10,
                  ),
                ]
              : const [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.formatShortWeekday(date),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 10.8,
                    color: isWeekend
                        ? const Color(0xFFFF6F95)
                        : const Color(0xCFCDC2F5),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 1),
            Text(
              '${date.day}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 13.4,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 0.5),
            Text(
              context.formatShortMonth(date),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: const Color(0xB59D91C9),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeworkSummaryCard extends StatelessWidget {
  const _HomeworkSummaryCard({
    required this.lessonsCount,
    required this.doneCount,
    required this.progressPercent,
  });

  final int lessonsCount;
  final int doneCount;
  final int? progressPercent;

  @override
  Widget build(BuildContext context) {
    final progressValue = progressPercent == null
        ? 0.0
        : (progressPercent!.clamp(0, 100) / 100.0);

    return Container(
      key: const Key('homework-summary-card'),
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF120E2B), Color(0xFF1A1238)],
        ),
        border: Border.all(color: const Color(0x7A392965)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF6D49D7), Color(0xFF8A5DFF)],
              ),
            ),
            child: const Icon(Icons.assignment_outlined,
                color: Color(0xFFE8DFFF), size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lessonsCount == 0
                      ? context.l10n.homeworkNoLessonsToday
                      : context.l10n.homeworkLessonsToday(lessonsCount),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14.8,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.homeworkCompletedCount(doneCount),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 11.8,
                        color: const Color(0xDAB8AEE2),
                      ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 54,
            height: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 54,
                  height: 54,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 6.2,
                    color: Color(0x4C8C72CA),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                SizedBox(
                  width: 54,
                  height: 54,
                  child: CircularProgressIndicator(
                    value: progressPercent == null ? 0 : progressValue,
                    strokeWidth: 6.2,
                    color: const Color(0xFF9B55FF),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(
                  progressPercent == null ? '—' : '${progressPercent!}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 15.4,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeworkModeToggle extends StatelessWidget {
  const _HomeworkModeToggle({
    required this.mode,
    required this.onModeChanged,
  });

  final _HomeworkMode mode;
  final ValueChanged<_HomeworkMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('homework-mode-toggle'),
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF130D2F), Color(0xFF1B133C)],
        ),
        border: Border.all(color: const Color(0x88372663)),
      ),
      child: Row(
        children: [
          _ModeSegment(
            label: context.l10n.homeworkShort,
            selected: mode == _HomeworkMode.homework,
            onTap: () => onModeChanged(_HomeworkMode.homework),
          ),
          _ModeSegment(
            label: context.l10n.homeworkLessonTopic,
            selected: mode == _HomeworkMode.topic,
            onTap: () => onModeChanged(_HomeworkMode.topic),
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF6E42E0), Color(0xFF8E56FF)],
                  )
                : null,
            color: selected ? null : Colors.transparent,
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14.0,
                    color: selected ? Colors.white : const Color(0xD0B8AEE2),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeworkLessonCard extends StatelessWidget {
  const _HomeworkLessonCard({
    required this.lesson,
    required this.mode,
    required this.isDone,
    required this.progressActive,
    required this.sendStatus,
    required this.isFirst,
    required this.isLast,
    required this.onLessonTap,
  });

  final LessonsEntity lesson;
  final _HomeworkMode mode;
  final bool isDone;
  final bool progressActive;
  final _LessonSendStatus sendStatus;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onLessonTap;

  @override
  Widget build(BuildContext context) {
    final subject = lesson.subjectName.trim().isEmpty
        ? context.l10n.homeworkSubjectMissing
        : lesson.subjectName.trim();
    final content = mode == _HomeworkMode.homework
        ? lesson.homeworkText.trim()
        : lesson.topic.trim();
    final fallback = mode == _HomeworkMode.homework
        ? context.l10n.homeworkDescriptionMissing
        : context.l10n.homeworkTopicMissing;
    final timeRange =
        (lesson.startTime.trim().isNotEmpty && lesson.endTime.trim().isNotEmpty)
            ? '${lesson.startTime.trim()} — ${lesson.endTime.trim()}'
            : '';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: sendStatus == _LessonSendStatus.sending ? null : onLessonTap,
      child: Container(
        key: Key('homework-lesson-card-${lesson.id}'),
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF110D2B), Color(0xFF1A1238)],
          ),
          border: Border.all(color: const Color(0x7A392965)),
        ),
        child: Row(
          children: [
            _TimelineNode(
              number: lesson.lessonNumber,
              isFirst: isFirst,
              isLast: isLast,
              active: progressActive,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 0.5),
                  Text(
                    content.isEmpty ? fallback : content,
                    softWrap: true,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 11.8,
                          color: const Color(0xD5B8AEE2),
                        ),
                  ),
                  if (timeRange.isNotEmpty) ...[
                    const SizedBox(height: 0.5),
                    Text(
                      timeRange,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontSize: 11.2,
                            color: const Color(0xC38177A8),
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            _LessonCompletionIndicator(
              done: isDone || sendStatus == _LessonSendStatus.sent,
              sending: sendStatus == _LessonSendStatus.sending,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.number,
    required this.isFirst,
    required this.isLast,
    required this.active,
  });

  final int number;
  final bool isFirst;
  final bool isLast;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: isFirst ? 18 : -6,
            bottom: isLast ? 18 : -6,
            child: Container(
              width: 2,
              color: active ? const Color(0x8A8F4CFF) : const Color(0x6548347A),
            ),
          ),
          if (!isLast)
            Positioned(
              bottom: -1,
              child: Container(
                width: 6.5,
                height: 6.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? const Color(0xD18F4CFF)
                      : const Color(0x7C5F4A9E),
                ),
              ),
            ),
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0x4E1A103D),
              border: Border.all(color: const Color(0x7A3B2A69)),
            ),
            child: Text(
              '$number',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14.2,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonCompletionIndicator extends StatelessWidget {
  const _LessonCompletionIndicator({
    required this.done,
    required this.sending,
  });

  final bool done;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    if (sending) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? const Color(0xFF59D84A) : Colors.transparent,
        border: Border.all(
          color: done ? const Color(0xFF59D84A) : const Color(0x8A6D60A5),
          width: 2,
        ),
      ),
      child: done
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
          : null,
    );
  }
}

class _HomeworkEmptyDayCard extends StatelessWidget {
  const _HomeworkEmptyDayCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('homework-empty-day-card'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF110D28), Color(0xFF1A1238)],
        ),
        border: Border.all(color: const Color(0x7A392965)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.coffee_rounded,
                color: Color(0xFFB6A6E6),
                size: 34,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.homeworkNoLessonsDay,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.homeworkRestHint,
                style: const TextStyle(
                  color: Color(0xCCB8AEE2),
                  fontSize: 13.6,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeworkWhatsAppButton extends StatelessWidget {
  const _HomeworkWhatsAppButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3CFF), Color(0xFFB15CFF)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x5E8F4CFF),
            blurRadius: 16,
            spreadRadius: 0.4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.8)),
                  ),
                  child: const Icon(
                    Icons.phone_in_talk_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontSize: 14.6,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoPreviewPage extends StatelessWidget {
  const _PhotoPreviewPage({
    required this.lesson,
    required this.mode,
    required this.photoPath,
  });

  final LessonsEntity lesson;
  final _HomeworkMode mode;
  final String photoPath;

  @override
  Widget build(BuildContext context) {
    final content = mode == _HomeworkMode.homework
        ? lesson.homeworkText.trim()
        : lesson.topic.trim();
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.homeworkPhotoPreview)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(KundiSpace.sm),
                child: ClipRRect(
                  borderRadius: KundiRadius.md,
                  child: Image.file(
                    File(photoPath),
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
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
                      context.l10n.homeworkSubjectLine(
                        lesson.subjectName.trim().isEmpty
                            ? context.l10n.commonNotSpecified
                            : lesson.subjectName.trim(),
                      ),
                    ),
                    const SizedBox(height: KundiSpace.xxs),
                    Text(
                      context.l10n.homeworkContentLine(
                        mode == _HomeworkMode.homework
                            ? context.l10n.homeworkAssignment
                            : context.l10n.homeworkTopic,
                        content.isEmpty
                            ? context.l10n.commonNotSpecified
                            : content,
                      ),
                    ),
                    const SizedBox(height: KundiSpace.xxs),
                    Text(
                      context.l10n.homeworkDateLine(
                        lesson.date.trim().isEmpty
                            ? context.l10n.homeworkDateMissing
                            : lesson.date.trim(),
                      ),
                    ),
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
                      child: Text(context.l10n.commonCancel),
                    ),
                  ),
                  const SizedBox(width: KundiSpace.xs),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_PhotoPreviewAction.retake),
                      child: Text(context.l10n.commonRetry),
                    ),
                  ),
                  const SizedBox(width: KundiSpace.xs),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_PhotoPreviewAction.send),
                      child: Text(context.l10n.commonSend),
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

String _normalizeDangerText(String value) {
  final lowered = value.toLowerCase().replaceAll('ё', 'е');
  return lowered
      .replaceAll(RegExp(r'[^a-zа-я0-9]+', unicode: true), ' ')
      .trim();
}
