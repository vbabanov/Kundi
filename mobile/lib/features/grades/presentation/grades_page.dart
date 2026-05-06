import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/kundi_tokens.dart';
import '../../../shared/widgets/kundi_surface.dart';
import '../application/grades_controller.dart';
import '../domain/grades_entity.dart';

enum _GradesTab { main, week, totals }

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  _GradesTab _tab = _GradesTab.main;
  String? _selectedWeekKey;
  final Set<String> _expandedTotals = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gradesControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Оценки')),
      body: KundiGradientBackground(
        child: state.when(
          data: (data) => _buildData(context, data),
          loading: () => const KundiStateBody.loading(),
          error: (error, _) => KundiStateBody.error(
            label: 'Не удалось загрузить оценки',
            onRetry: () => ref.read(gradesControllerProvider.notifier).refreshFromCache(),
          ),
        ),
      ),
    );
  }

  Widget _buildData(BuildContext context, GradesScreenData data) {
    if (data.isEmpty) {
      return const KundiStateBody.empty(label: 'Оценки пока не загружены');
    }

    _selectedWeekKey ??= data.availableWeeks.isNotEmpty ? data.availableWeeks.last.weekKey : null;
    if (_selectedWeekKey != null && !data.availableWeeks.any((w) => w.weekKey == _selectedWeekKey)) {
      _selectedWeekKey = data.availableWeeks.isNotEmpty ? data.availableWeeks.last.weekKey : null;
    }

    return Column(
      children: [
        const SizedBox(height: KundiSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
          child: Row(
            children: [
              _tabChip('Главная', _GradesTab.main, 'grades-tab-main'),
              const SizedBox(width: KundiSpace.xs),
              _tabChip('Неделя', _GradesTab.week, 'grades-tab-week'),
              const SizedBox(width: KundiSpace.xs),
              _tabChip('Итоговые', _GradesTab.totals, 'grades-tab-totals'),
            ],
          ),
        ),
        const SizedBox(height: KundiSpace.xs),
        Expanded(
          child: switch (_tab) {
            _GradesTab.main => _mainTab(context, data),
            _GradesTab.week => _weekTab(context, data),
            _GradesTab.totals => _totalsTab(context, data),
          },
        ),
      ],
    );
  }

  Widget _tabChip(String label, _GradesTab tab, String keyValue) {
    final selected = tab == _tab;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: KundiRadius.pill,
          onTap: () => setState(() => _tab = tab),
          child: Container(
            key: Key(keyValue),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: KundiRadius.pill,
              color: selected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.28)
                  : Theme.of(context).colorScheme.kundiElevated.withValues(alpha: 0.5),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.58)
                    : Theme.of(context).colorScheme.kundiBorder,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mainTab(BuildContext context, GradesScreenData data) {
    final latest = data.latestRegularResults.take(8).toList(growable: false);
    if (latest.isEmpty) {
      return const KundiEmptyState(icon: Icons.auto_graph_outlined, label: 'Последние оценки пока отсутствуют');
    }

    final summativePreview = data.summativeBySubject.take(4).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(KundiSpace.sm, KundiSpace.xs, KundiSpace.sm, KundiSpace.sm),
      children: [
        const KundiSectionHeader(title: 'Последние оценки'),
        const SizedBox(height: KundiSpace.xs),
        Wrap(
          spacing: KundiSpace.xs,
          runSpacing: KundiSpace.xs,
          children: latest.map((item) {
            return SizedBox(
              width: (MediaQuery.of(context).size.width - 36) / 2,
              child: KundiSectionCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.subjectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _QualityBadge(value: item.value, palette: _gradePaletteFromMark(item.value)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.recordedOn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.kundiTextSecondary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: KundiSpace.sm),
        const KundiSectionHeader(title: 'СОР / СОЧ'),
        const SizedBox(height: KundiSpace.xs),
        if (summativePreview.isEmpty)
          const KundiEmptyState(icon: Icons.rule_folder_outlined, label: 'СОР/СОЧ пока отсутствуют')
        else
          ...summativePreview.map(
            (item) => KundiSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.subjectName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.items.take(4).map((mark) {
                      return _QualityBadge(
                        value: mark.value,
                        palette: _paletteForSummative(mood: mark.mood, value: mark.value),
                      );
                    }).toList(growable: false),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _weekTab(BuildContext context, GradesScreenData data) {
    final weeks = data.availableWeeks;
    if (weeks.isEmpty) {
      return const KundiEmptyState(icon: Icons.calendar_today_outlined, label: 'Недельные данные недоступны');
    }

    final index = weeks.indexWhere((w) => w.weekKey == _selectedWeekKey);
    final safeIndex = index < 0 ? weeks.length - 1 : index;
    final week = weeks[safeIndex];
    final rows = data.weeklyRowsByWeek[week.weekKey] ?? const <WeeklySubjectGradesRow>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
          child: KundiSectionCard(
            margin: EdgeInsets.zero,
            child: Row(
              children: [
                IconButton(
                  onPressed: safeIndex > 0 ? () => setState(() => _selectedWeekKey = weeks[safeIndex - 1].weekKey) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(week.label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  onPressed: safeIndex < weeks.length - 1 ? () => setState(() => _selectedWeekKey = weeks[safeIndex + 1].weekKey) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: KundiSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final geometry = _WeekGridGeometry.fromWidth(constraints.maxWidth);
              return KundiSectionCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: geometry.subjectColumnWidth,
                      child: Text(
                        'Предмет',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    SizedBox(width: geometry.gap),
                    ...const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'].map(
                      (day) => SizedBox(
                        width: geometry.dayColumnWidth,
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: KundiSpace.xs),
        Expanded(
          child: rows.isEmpty
              ? const KundiEmptyState(icon: Icons.grid_view_outlined, label: 'За выбранную неделю оценок нет')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final geometry = _WeekGridGeometry.fromWidth(constraints.maxWidth);
                        return KundiSectionCard(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: geometry.subjectColumnWidth,
                                child: Text(
                                  row.subjectName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              SizedBox(width: geometry.gap),
                              ...List.generate(7, (weekday) {
                                final cell = row.cellsByWeekday[weekday + 1];
                                return SizedBox(
                                  width: geometry.dayColumnWidth,
                                  child: Center(child: _weekCellWidget(context, cell)),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _weekCellWidget(BuildContext context, WeeklyGradeCell? cell) {
    if (cell == null) return const SizedBox.shrink();

    final mark = _pickDisplayMark(cell.regularMarks);
    if (mark.isNotEmpty) {
      return _QualityBadge(
        value: mark,
        palette: mark.contains('/') ? _gradePaletteFromFraction(mark) : _gradePaletteFromMark(mark),
        compact: true,
      );
    }

    final attendance = _pickAttendanceCode(cell);
    if (attendance != null) {
      return _QualityBadge(value: attendance, palette: _attendancePalette(attendance), compact: true);
    }

    if (cell.hasLesson || cell.showDot) {
      return Text(
        '·',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.kundiTextTertiary,
            ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _totalsTab(BuildContext context, GradesScreenData data) {
    final sections = data.aggregatesBySubject;
    if (sections.isEmpty) {
      return const KundiEmptyState(icon: Icons.table_chart_outlined, label: 'Итоговые данные пока недоступны');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _TotalsGridGeometry.fromWidth(constraints.maxWidth);
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
          children: [
            KundiSectionCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: _TotalsHeaderRow(geometry: geometry),
            ),
            const SizedBox(height: KundiSpace.xs),
            ...sections.map((section) {
              final termMap = <int, _QuarterMarks>{};
              for (final term in [1, 2, 3, 4]) {
                termMap[term] = _quarterMarksFor(section.summativeItems, term);
              }
              final quarterValues = _summaryQuarterValues(section);
              final yearValue = _summaryYearValue(section);
              final expanded = _expandedTotals.contains(section.subjectKey);

              return KundiSectionCard(
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: Key('grades-aggregate-subject-${section.subjectKey}'),
                    initiallyExpanded: expanded,
                    onExpansionChanged: (value) {
                      setState(() {
                        if (value) {
                          _expandedTotals.add(section.subjectKey);
                        } else {
                          _expandedTotals.remove(section.subjectKey);
                        }
                      });
                    },
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8, bottom: 6),
                    title: _TotalsCollapsedRow(
                      geometry: geometry,
                      subjectName: section.subjectName,
                      quarterValues: quarterValues,
                      yearValue: yearValue,
                      expanded: expanded,
                    ),
                    children: [
                      for (final term in [1, 2, 3, 4])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _QuarterDetailRow(term: term, marks: termMap[term]!),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  _QuarterMarks _quarterMarksFor(List<SummativeItem> items, int termNo) {
    final termTag = '$termNo';
    final scoped = items.where((item) => item.termLabel.toLowerCase().contains(termTag)).toList(growable: false);

    final sor = <_ValueMood>[];
    final soch = <_ValueMood>[];

    for (final item in scoped) {
      final value = item.value.trim();
      if (value.isEmpty || value == '-') continue;
      final vm = _ValueMood(value: value, mood: item.mood.trim());
      if (item.kind.toLowerCase() == 'sor') {
        sor.add(vm);
      } else if (item.kind.toLowerCase() == 'soch') {
        soch.add(vm);
      }
    }

    return _QuarterMarks(sor: sor, soch: soch);
  }

  List<String> _summaryQuarterValues(SubjectAggregateSection section) {
    final values = List<String>.filled(4, '-');
    for (final item in section.termItems) {
      final termNo = item.termNo;
      if (termNo == null || termNo < 1 || termNo > 4) continue;
      final normalized = item.value.trim();
      values[termNo - 1] = normalized.isEmpty ? '-' : normalized;
    }
    return values;
  }

  String _summaryYearValue(SubjectAggregateSection section) {
    if (section.yearItems.isEmpty) return '-';
    final normalized = section.yearItems.first.value.trim();
    return normalized.isEmpty ? '-' : normalized;
  }
}

class _WeekGridGeometry {
  const _WeekGridGeometry({required this.subjectColumnWidth, required this.dayColumnWidth, required this.gap});

  final double subjectColumnWidth;
  final double dayColumnWidth;
  final double gap;

  static _WeekGridGeometry fromWidth(double maxWidth) {
    const gap = 4.0;
    final subjectWidth = maxWidth < 360 ? 84.0 : 102.0;
    final dayWidth = ((maxWidth - subjectWidth - gap) / 7).clamp(12.0, 24.0);
    return _WeekGridGeometry(subjectColumnWidth: subjectWidth, dayColumnWidth: dayWidth, gap: gap);
  }
}

class _TotalsGridGeometry {
  const _TotalsGridGeometry({required this.gradeColumnWidth, required this.chevronWidth});

  final double gradeColumnWidth;
  final double chevronWidth;

  static _TotalsGridGeometry fromWidth(double maxWidth) {
    final gradeWidth = maxWidth < 360 ? 22.0 : 26.0;
    return _TotalsGridGeometry(gradeColumnWidth: gradeWidth, chevronWidth: 18.0);
  }
}

class _TotalsHeaderRow extends StatelessWidget {
  const _TotalsHeaderRow({required this.geometry});

  final _TotalsGridGeometry geometry;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.kundiTextSecondary,
          fontWeight: FontWeight.w700,
        );
    return Row(
      children: [
        const Expanded(child: SizedBox()),
        ...const ['1', '2', '3', '4', 'Год'].map(
          (label) => SizedBox(
            width: geometry.gradeColumnWidth,
            child: Text(label, textAlign: TextAlign.center, style: labelStyle),
          ),
        ),
        SizedBox(width: geometry.chevronWidth),
      ],
    );
  }
}

class _TotalsCollapsedRow extends StatelessWidget {
  const _TotalsCollapsedRow({
    required this.geometry,
    required this.subjectName,
    required this.quarterValues,
    required this.yearValue,
    required this.expanded,
  });

  final _TotalsGridGeometry geometry;
  final String subjectName;
  final List<String> quarterValues;
  final String yearValue;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            subjectName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ...quarterValues.map(
          (value) => SizedBox(
            width: geometry.gradeColumnWidth,
            child: Center(child: _InlineQuarterMark(value: value, palette: _gradePaletteFromMark(value))),
          ),
        ),
        SizedBox(
          width: geometry.gradeColumnWidth,
          child: Center(child: _InlineQuarterMark(value: yearValue, palette: _gradePaletteFromMark(yearValue))),
        ),
        SizedBox(
          width: geometry.chevronWidth,
          child: Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: Theme.of(context).colorScheme.kundiTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _QuarterDetailRow extends StatelessWidget {
  const _QuarterDetailRow({required this.term, required this.marks});

  final int term;
  final _QuarterMarks marks;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.kundiTextSecondary;
    if (marks.sor.isEmpty && marks.soch.isEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text('$term четв.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
          ),
          Expanded(
            child: Text('Пока нет данных', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text('$term четв.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Text('СОР', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: muted, fontWeight: FontWeight.w700)),
              ...marks.sor.map(
                (vm) => _QualityBadge(
                  value: vm.value,
                  palette: _paletteForSummative(mood: vm.mood, value: vm.value),
                  compact: true,
                ),
              ),
              if (marks.soch.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text('СОЧ', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: muted, fontWeight: FontWeight.w700)),
                ...marks.soch.map(
                  (vm) => _QualityBadge(
                    value: vm.value,
                    palette: _paletteForSummative(mood: vm.mood, value: vm.value),
                    compact: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ValueMood {
  const _ValueMood({required this.value, required this.mood});

  final String value;
  final String mood;
}

class _QuarterMarks {
  const _QuarterMarks({required this.sor, required this.soch});

  final List<_ValueMood> sor;
  final List<_ValueMood> soch;
}

class _InlineQuarterMark extends StatelessWidget {
  const _InlineQuarterMark({required this.value, required this.palette});

  final String value;
  final _GradePalette palette;

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim().isEmpty ? '-' : value.trim();
    final isMuted = normalized == '-' || palette.muted;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        color: palette.fill,
        border: Border.all(color: palette.border),
      ),
      child: Text(
        normalized,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isMuted ? palette.text : Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.value, required this.palette, this.compact = false});

  final String value;
  final _GradePalette palette;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim().isEmpty ? '-' : value.trim();
    final isMuted = normalized == '-' || palette.muted;
    return Container(
      constraints: BoxConstraints(minWidth: compact ? 18 : 28),
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 9, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 7 : 10),
        color: palette.fill,
        border: Border.all(color: palette.border),
      ),
      child: Text(
        normalized,
        maxLines: 1,
        softWrap: false,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isMuted ? palette.text : Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
      ),
    );
  }
}

class _GradePalette {
  const _GradePalette({required this.fill, required this.border, required this.text, this.muted = false});

  final Color fill;
  final Color border;
  final Color text;
  final bool muted;
}

_GradePalette _paletteForSummative({required String mood, required String value}) {
  final moodPalette = _paletteFromMood(mood);
  if (moodPalette != null) return moodPalette;
  return _gradePaletteFromFraction(value);
}

String _pickDisplayMark(List<String> rawMarks) {
  for (final raw in rawMarks) {
    final value = raw.trim();
    if (value.isEmpty || value == '-' || _normalizeAttendance(value) != null) {
      continue;
    }
    if (RegExp(r'^\d+$').hasMatch(value) || RegExp(r'^\d+\s*/\s*\d+$').hasMatch(value)) {
      return value.replaceAll(RegExp(r'\s+'), '');
    }
  }
  return '';
}

String? _pickAttendanceCode(WeeklyGradeCell cell) {
  for (final raw in cell.attendanceCodes) {
    final code = _normalizeAttendance(raw);
    if (code != null) return code;
  }
  // Fallback for payloads where attendance markers ended up in regular marks.
  for (final raw in cell.regularMarks) {
    final code = _normalizeAttendance(raw);
    if (code != null) return code;
  }
  return null;
}

_GradePalette? _paletteFromMood(String mood) {
  final m = mood.trim().toLowerCase();
  if (m.isEmpty || m == 'unknown') return null;
  const good = {'good', 'excellent', 'high', 'positive'};
  const neutral = {'average', 'neutral', 'mid'};
  const bad = {'bad', 'poor', 'low', 'negative'};
  if (good.contains(m)) return _solidPalette(const Color(0xFF34C759));
  if (neutral.contains(m)) return _solidPalette(const Color(0xFFFF9500));
  if (bad.contains(m)) return _solidPalette(const Color(0xFFFF3B30));
  return null;
}

_GradePalette _gradePaletteFromMark(String raw) {
  final value = int.tryParse(raw.trim());
  if (value == null) return _mutedPalette();

  if (value <= 5) {
    if (value == 5) return _solidPalette(const Color(0xFF34C759));
    if (value == 4) return _solidPalette(const Color(0xFFFF9500));
    if (value == 3) return _solidPalette(const Color(0xFFFF6A00));
    return _solidPalette(const Color(0xFFFF3B30));
  }

  if (value >= 9) return _solidPalette(const Color(0xFF34C759));
  if (value >= 7) return _solidPalette(const Color(0xFFFF9500));
  if (value >= 5) return _solidPalette(const Color(0xFFFF6A00));
  return _solidPalette(const Color(0xFFFF3B30));
}

_GradePalette _gradePaletteFromFraction(String raw) {
  final parts = raw.split('/');
  if (parts.length != 2) return _gradePaletteFromMark(raw);

  final value = double.tryParse(parts[0].trim());
  final maxValue = double.tryParse(parts[1].trim());
  if (value == null || maxValue == null || maxValue <= 0) return _mutedPalette();

  final percent = value / maxValue;
  if (percent >= 0.8) return _solidPalette(const Color(0xFF34C759));
  if (percent >= 0.6) return _solidPalette(const Color(0xFFFF9500));
  return _solidPalette(const Color(0xFFFF3B30));
}

_GradePalette _attendancePalette(String code) {
  switch (code) {
    case 'О':
      return _solidPalette(const Color(0xFFFF9500));
    case 'Б':
      return _solidPalette(const Color(0xFF4F9DFF));
    case 'Н':
      return _solidPalette(const Color(0xFFFF3B30));
    default:
      return _mutedPalette();
  }
}

String? _normalizeAttendance(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return null;

  if (value == 'н' || value == 'absent') return 'Н';
  if (value == 'б' || value == 'excused') return 'Б';
  if (value == 'о' || value == 'late') return 'О';

  // handles occasional mojibake variants
  if (value.contains('abs')) return 'Н';
  if (value.contains('exc') || value.contains('бол')) return 'Б';
  if (value.contains('lat') || value.contains('опоз')) return 'О';

  return null;
}

_GradePalette _solidPalette(Color color) {
  return _GradePalette(fill: color, border: color, text: Colors.white);
}

_GradePalette _mutedPalette() {
  const muted = Color(0xFF8E82A8);
  return _GradePalette(
    fill: muted.withValues(alpha: 0.16),
    border: muted.withValues(alpha: 0.55),
    text: muted.withValues(alpha: 0.95),
    muted: true,
  );
}
