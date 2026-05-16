import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/kundi_tokens.dart';
import '../../../shared/widgets/kundi_surface.dart';
import '../application/grades_controller.dart';
import '../domain/grades_entity.dart';

enum _GradesTab { main, week, totals }

enum _TotalsPeriod { q1, q2, q3, q4, year }

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  _GradesTab _tab = _GradesTab.main;
  _TotalsPeriod _totalsPeriod = _TotalsPeriod.year;
  String? _selectedWeekKey;
  int _selectedWeekday = 1;
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
            onRetry: () =>
                ref.read(gradesControllerProvider.notifier).refreshFromCache(),
          ),
        ),
      ),
    );
  }

  Widget _buildData(BuildContext context, GradesScreenData data) {
    if (data.isEmpty) {
      return const KundiStateBody.empty(label: 'Оценки пока не загружены');
    }

    _selectedWeekKey ??= data.availableWeeks.isNotEmpty
        ? data.availableWeeks.last.weekKey
        : null;
    if (_selectedWeekKey != null &&
        !data.availableWeeks.any((w) => w.weekKey == _selectedWeekKey)) {
      _selectedWeekKey = data.availableWeeks.isNotEmpty
          ? data.availableWeeks.last.weekKey
          : null;
    }
    final todayWeekday = DateTime.now().weekday.clamp(1, 7);
    if (_selectedWeekday < 1 || _selectedWeekday > 7) {
      _selectedWeekday = todayWeekday;
    }

    return Column(
      children: [
        const SizedBox(height: KundiSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
          child: Container(
            height: 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xB24A327D)),
              gradient: const LinearGradient(
                colors: [Color(0xE611102B), Color(0xE6171033)],
              ),
            ),
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
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _tab = tab),
          child: Container(
            key: Key(keyValue),
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: selected
                  ? const LinearGradient(
                      colors: [Color(0xFF8B46E8), Color(0xFFA855F7)])
                  : null,
              color: selected ? null : Colors.transparent,
              border: Border.all(
                  color:
                      selected ? const Color(0xCCA67CFB) : Colors.transparent),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                          color: Color(0x4A9B55FF),
                          blurRadius: 10,
                          spreadRadius: 1)
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : const Color(0xD9B8AEE2),
                      fontSize: selected ? 14.3 : 13.6,
                    ),
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
      return const KundiEmptyState(
          icon: Icons.auto_graph_outlined,
          label: 'Последние оценки пока отсутствуют');
    }

    final summativePreview =
        data.summativeBySubject.take(4).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          KundiSpace.sm, KundiSpace.xs, KundiSpace.sm, KundiSpace.sm),
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
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _QualityBadge(
                            value: item.value,
                            palette: _gradePaletteFromMark(item.value)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.recordedOn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .kundiTextSecondary,
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
          const KundiEmptyState(
              icon: Icons.rule_folder_outlined,
              label: 'СОР/СОЧ пока отсутствуют')
        else
          ...summativePreview.map(
            (item) => KundiSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.subjectName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.items.take(4).map((mark) {
                      return _QualityBadge(
                        value: mark.value,
                        palette: _paletteForSummative(
                            mood: mark.mood, value: mark.value),
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
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            KundiSpace.sm, KundiSpace.xs, KundiSpace.sm, KundiSpace.md),
        children: const [
          _WeekEmptyStateCard(
            title: 'За неделю оценок пока нет',
            subtitle: 'Когда появятся новые оценки, я покажу их здесь.',
          ),
        ],
      );
    }

    final index = weeks.indexWhere((w) => w.weekKey == _selectedWeekKey);
    final safeIndex = index < 0 ? weeks.length - 1 : index;
    final week = weeks[safeIndex];
    final rows =
        data.weeklyRowsByWeek[week.weekKey] ?? const <WeeklySubjectGradesRow>[];
    final tableRows = _buildWeekTableRows(data, rows);
    final weekdayDates = _resolveWeekdayDates(week, rows);
    final visibleWeekdays = _resolveVisibleWeekdays(rows);
    final selectedWeekday = _selectedWeekday;
    final summary = _computeWeekSummary(tableRows, visibleWeekdays);
    final hasWeeklySignals = rows.any(
      (row) => row.cellsByWeekday.values.any(
        (cell) =>
            cell.hasLesson ||
            cell.regularMarks.isNotEmpty ||
            cell.attendanceCodes.isNotEmpty,
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KundiSpace.sm),
          child: Container(
            key: const Key('grades-week-switcher'),
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF11112B), Color(0xFF171237)],
              ),
              border: Border.all(color: const Color(0xB2302654)),
            ),
            child: Row(
              children: [
                IconButton(
                  key: const Key('grades-week-prev'),
                  onPressed: safeIndex > 0
                      ? () => setState(() {
                            _selectedWeekKey = weeks[safeIndex - 1].weekKey;
                            _selectedWeekday = 1;
                          })
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(_formatWeekRangeLabel(week),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          )),
                ),
                IconButton(
                  key: const Key('grades-week-next'),
                  onPressed: safeIndex < weeks.length - 1
                      ? () => setState(() {
                            _selectedWeekKey = weeks[safeIndex + 1].weekKey;
                            _selectedWeekday = 1;
                          })
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(KundiSpace.sm, 4, KundiSpace.sm, 0),
          child: _WeekDaySelector(
            selectedWeekday: selectedWeekday,
            activeWeekdays: visibleWeekdays,
            weekdayDates: weekdayDates,
            onChanged: (weekday) => setState(() => _selectedWeekday = weekday),
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(KundiSpace.sm, 6, KundiSpace.sm, 0),
          child: const _WeekLegendCard(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: !hasWeeklySignals || tableRows.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(
                      KundiSpace.sm, 0, KundiSpace.sm, KundiSpace.md),
                  children: const [
                    _WeekEmptyStateCard(
                      title: 'За неделю оценок пока нет',
                      subtitle:
                          'Когда появятся новые оценки, я покажу их здесь.',
                    ),
                  ],
                )
              : ListView(
                  key: const Key('grades-week-rows-scroll'),
                  padding: const EdgeInsets.fromLTRB(
                      KundiSpace.sm, 0, KundiSpace.sm, KundiSpace.sm),
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final geometry = _WeekTableGeometry.fromWidth(
                            constraints.maxWidth, visibleWeekdays.length);
                        final selectedIndex =
                            visibleWeekdays.indexOf(selectedWeekday);
                        final dayAreaWidth =
                            constraints.maxWidth - geometry.subjectColumnWidth;
                        final dayColumnWidth =
                            dayAreaWidth / visibleWeekdays.length;
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0x40110E2B), Color(0x30171035)],
                            ),
                            border: Border.all(color: const Color(0xA62F2850)),
                          ),
                          child: Stack(
                            children: [
                              if (selectedIndex >= 0)
                                Positioned(
                                  left: geometry.subjectColumnWidth +
                                      (dayColumnWidth * selectedIndex),
                                  top: 0,
                                  bottom: 0,
                                  width: dayColumnWidth,
                                  child: IgnorePointer(
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Color(0x205532A9),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(0x166E45DD),
                                            blurRadius: 8,
                                            spreadRadius: -1.5,
                                            offset: Offset(-1, 0),
                                          ),
                                          BoxShadow(
                                            color: Color(0x166E45DD),
                                            blurRadius: 8,
                                            spreadRadius: -1.5,
                                            offset: Offset(1, 0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              Column(
                                children: [
                                  for (var i = 0; i < tableRows.length; i++)
                                    _WeekTableRow(
                                      row: tableRows[i],
                                      geometry: geometry,
                                      visibleWeekdays: visibleWeekdays,
                                      showDivider: i != tableRows.length - 1,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              KundiSpace.sm, 0, KundiSpace.sm, KundiSpace.xs),
          child: _WeekSummaryCard(
            summary: summary,
          ),
        ),
      ],
    );
  }

  List<_WeekTableRowData> _buildWeekTableRows(
    GradesScreenData data,
    List<WeeklySubjectGradesRow> rows,
  ) {
    final grouped = <String, _WeekTableRowData>{};
    final order = <String>[];

    _WeekTableRowData ensureRow(String subjectKey, String subjectName) {
      final canonical = _canonicalSubjectName(subjectName);
      if (!grouped.containsKey(canonical)) {
        grouped[canonical] = _WeekTableRowData(
          subjectKey: subjectKey,
          subjectName: subjectName.trim().isEmpty ? subjectKey : subjectName,
          cells: <int, _WeekCellDisplay>{},
        );
        order.add(canonical);
      }
      return grouped[canonical]!;
    }

    for (final row in rows) {
      final target = ensureRow(row.subjectKey, row.subjectName);
      for (var weekday = 1; weekday <= 7; weekday++) {
        final current = target.cells[weekday] ?? const _WeekCellDisplay.empty();
        final source = row.cellsByWeekday[weekday];
        if (source == null) {
          target.cells[weekday] = current;
          continue;
        }
        final marks = source.regularMarks
            .map((m) => m.trim())
            .where((m) =>
                m.isNotEmpty && m != '-' && _normalizeAttendance(m) == null)
            .toList(growable: false);
        final attendance = _pickAttendanceCode(source);
        final mergedMarks = <String>[
          ...current.marks,
          ...marks.where((m) => !current.marks.contains(m)),
        ];
        final mergedAttendance = current.attendance ?? attendance;
        final hasLesson = current.hasLesson || source.hasLesson;
        final showDot =
            hasLesson && mergedMarks.isEmpty && mergedAttendance == null;
        target.cells[weekday] = _WeekCellDisplay(
          marks: mergedMarks,
          attendance: mergedAttendance,
          hasLesson: hasLesson,
          showDot: showDot,
        );
      }
    }

    void addFallback(String key, String name) {
      final cleaned = name.trim();
      if (cleaned.isEmpty) return;
      ensureRow(key, cleaned);
    }

    for (final item in data.aggregatesBySubject) {
      addFallback(item.subjectKey, item.subjectName);
    }
    for (final item in data.summativeBySubject) {
      addFallback(item.subjectKey, item.subjectName);
    }
    for (final item in data.latestRegularResults) {
      addFallback(item.subjectKey, item.subjectName);
    }

    final result = <_WeekTableRowData>[];
    for (final canonical in order) {
      final row = grouped[canonical]!;
      for (var weekday = 1; weekday <= 7; weekday++) {
        row.cells.putIfAbsent(weekday, () => const _WeekCellDisplay.empty());
      }
      result.add(row);
    }
    return result;
  }

  String _canonicalSubjectName(String input) {
    return input
        .replaceAll(RegExp(r'[\u200B-\u200F\uFEFF]'), '')
        .replaceAll('ё', 'е')
        .replaceAll('Ё', 'Е')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Map<int, String?> _resolveWeekdayDates(
    GradesWeekOption week,
    List<WeeklySubjectGradesRow> rows,
  ) {
    final dates = <int, String?>{};
    for (var weekday = 1; weekday <= 7; weekday++) {
      String? raw;
      for (final row in rows) {
        final cell = row.cellsByWeekday[weekday];
        if (cell != null && cell.date.trim().isNotEmpty) {
          raw = cell.date.trim();
          break;
        }
      }
      if (raw == null) {
        final base = DateTime.tryParse(week.weekStartDate);
        if (base != null) {
          raw = base
              .add(Duration(days: weekday - 1))
              .toIso8601String()
              .split('T')
              .first;
        }
      }
      dates[weekday] = raw == null ? null : _shortDate(raw);
    }
    return dates;
  }

  List<int> _resolveVisibleWeekdays(List<WeeklySubjectGradesRow> rows) {
    bool hasSignalsFor(int weekday) {
      for (final row in rows) {
        final cell = row.cellsByWeekday[weekday];
        if (cell == null) continue;
        if (cell.hasLesson ||
            cell.regularMarks.any((m) => m.trim().isNotEmpty) ||
            cell.attendanceCodes.any((c) => c.trim().isNotEmpty)) {
          return true;
        }
      }
      return false;
    }

    final hasSaturday = hasSignalsFor(6);
    final hasSunday = hasSignalsFor(7);
    final lastWeekday = hasSunday ? 7 : (hasSaturday ? 6 : 5);
    return <int>[
      for (var weekday = 1; weekday <= lastWeekday; weekday++) weekday
    ];
  }

  String _formatWeekRangeLabel(GradesWeekOption week) {
    final start = DateTime.tryParse(week.weekStartDate);
    final end = DateTime.tryParse(week.weekEndDate);
    if (start == null || end == null) return week.label;
    const months = <int, String>{
      1: 'января',
      2: 'февраля',
      3: 'марта',
      4: 'апреля',
      5: 'мая',
      6: 'июня',
      7: 'июля',
      8: 'августа',
      9: 'сентября',
      10: 'октября',
      11: 'ноября',
      12: 'декабря',
    };
    final month = start.month == end.month
        ? (months[start.month] ?? '')
        : '${months[start.month]} — ${months[end.month]}';
    return '${start.day} — ${end.day} $month'.trim();
  }

  _WeekSummaryData _computeWeekSummary(
    List<_WeekTableRowData> rows,
    List<int> visibleWeekdays,
  ) {
    var marksCount = 0;
    final numeric = <double>[];
    var lessonCount = 0;
    var absentCount = 0;
    for (final row in rows) {
      for (final weekday in visibleWeekdays) {
        final cell = row.cells[weekday];
        if (cell == null) continue;
        for (final mark in cell.marks) {
          marksCount++;
          final parsed = double.tryParse(mark.replaceAll(',', '.'));
          if (parsed != null) numeric.add(parsed);
        }
        if (cell.hasLesson ||
            cell.marks.isNotEmpty ||
            cell.attendance != null) {
          lessonCount++;
          if (cell.attendance == 'Н') absentCount++;
        }
      }
    }
    final avg = numeric.isEmpty
        ? null
        : numeric.reduce((a, b) => a + b) / numeric.length;
    final attendancePercent = lessonCount == 0
        ? null
        : (((lessonCount - absentCount) / lessonCount) * 100).round();
    return _WeekSummaryData(
      marksCount: marksCount,
      average: avg,
      attendancePercent: attendancePercent,
    );
  }

  String? _shortDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final day = parts[2].padLeft(2, '0');
    final month = parts[1].padLeft(2, '0');
    return '$day.$month';
  }

  Widget _totalsTab(BuildContext context, GradesScreenData data) {
    final sections = data.aggregatesBySubject;
    if (sections.isEmpty) {
      return const KundiEmptyState(
          icon: Icons.table_chart_outlined,
          label: 'Итоговые данные пока недоступны');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _TotalsGridGeometry.fromWidth(constraints.maxWidth);
        final selectedTerm = _selectedTermNo(_totalsPeriod);
        final periodAverage = _computePeriodAverage(sections, selectedTerm);
        return ListView(
          padding: const EdgeInsets.fromLTRB(
              KundiSpace.sm, 0, KundiSpace.sm, KundiSpace.md),
          children: [
            _TotalsPeriodSelector(
              selected: _totalsPeriod,
              onChanged: (value) => setState(() => _totalsPeriod = value),
            ),
            const SizedBox(height: 10),
            _YearAverageHeroCard(
              title:
                  selectedTerm == null ? 'Средний балл за год' : 'Средний балл',
              average: periodAverage,
            ),
            const SizedBox(height: 6),
            ...sections.map((section) {
              final termMap = <int, _QuarterMarks>{};
              for (final term in [1, 2, 3, 4]) {
                termMap[term] = _quarterMarksFor(section.summativeItems, term);
              }
              final quarterValues = _summaryQuarterValues(section);
              final yearValue = _summaryYearValue(section);
              final expanded = _expandedTotals.contains(section.subjectKey);

              if (selectedTerm == null) {
                return Container(
                  key: Key('grades-aggregate-subject-${section.subjectKey}'),
                  margin: const EdgeInsets.only(bottom: 3),
                  constraints: const BoxConstraints(minHeight: 64),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF191136), Color(0xFF21143F)],
                    ),
                    border: Border.all(color: const Color(0xBF31235E)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A100C2A),
                        blurRadius: 8,
                        spreadRadius: 0.4,
                      ),
                    ],
                  ),
                  child: _TotalsCollapsedRow(
                    geometry: geometry,
                    subjectKey: section.subjectKey,
                    subjectName: section.subjectName,
                    quarterValues: quarterValues,
                    yearValue: yearValue,
                    selectedTerm: selectedTerm,
                    expanded: false,
                    showChevron: false,
                  ),
                );
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF191136), Color(0xFF21143F)],
                  ),
                  border: Border.all(color: const Color(0xBF31235E)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A100C2A),
                      blurRadius: 8,
                      spreadRadius: 0.4,
                    ),
                  ],
                ),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
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
                    showTrailingIcon: false,
                    childrenPadding: const EdgeInsets.only(top: 6, bottom: 1),
                    title: _TotalsCollapsedRow(
                      geometry: geometry,
                      subjectKey: section.subjectKey,
                      subjectName: section.subjectName,
                      quarterValues: quarterValues,
                      yearValue: yearValue,
                      selectedTerm: selectedTerm,
                      expanded: expanded,
                      showChevron: true,
                    ),
                    children: [
                      _QuarterDetailRow(
                        marks: termMap[selectedTerm]!,
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
    final scoped = items
        .where((item) => item.termLabel.toLowerCase().contains(termTag))
        .toList(growable: false);

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
    if (section.yearItems.isEmpty) return '—';
    final normalized = section.yearItems.first.value.trim();
    return _displayGradeOrDash(normalized);
  }

  int? _selectedTermNo(_TotalsPeriod period) {
    return switch (period) {
      _TotalsPeriod.q1 => 1,
      _TotalsPeriod.q2 => 2,
      _TotalsPeriod.q3 => 3,
      _TotalsPeriod.q4 => 4,
      _TotalsPeriod.year => null,
    };
  }

  double? _computePeriodAverage(
      List<SubjectAggregateSection> sections, int? termNo) {
    final values = <double>[];
    for (final section in sections) {
      if (termNo != null) {
        final quarterValue = _summaryQuarterValues(section)[termNo - 1];
        final quarter = double.tryParse(quarterValue.replaceAll(',', '.'));
        if (quarter != null) values.add(quarter);
        continue;
      }
      final year =
          double.tryParse(_summaryYearValue(section).replaceAll(',', '.'));
      if (year != null) {
        values.add(year);
      }
    }
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

class _TotalsPeriodSelector extends StatelessWidget {
  const _TotalsPeriodSelector(
      {required this.selected, required this.onChanged});

  final _TotalsPeriod selected;
  final ValueChanged<_TotalsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = <(_TotalsPeriod, String)>[
      (_TotalsPeriod.q1, '1'),
      (_TotalsPeriod.q2, '2'),
      (_TotalsPeriod.q3, '3'),
      (_TotalsPeriod.q4, '4'),
      (_TotalsPeriod.year, 'Год'),
    ];

    return Container(
      height: 52,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: const LinearGradient(
          colors: [Color(0xFF11102B), Color(0xFF171033)],
        ),
        border: Border.all(color: const Color(0xB24A327D)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: List.generate(
                items.length - 1,
                (index) => Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 1,
                      height: 18,
                      color: const Color(0x384A327D),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: items.map((entry) {
              final active = entry.$1 == selected;
              final isYear = entry.$1 == _TotalsPeriod.year;
              final periodLabel = entry.$2 == 'Год' ? 'year' : entry.$2;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    key: Key('grades-totals-period-$periodLabel'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onChanged(entry.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.center,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: active
                            ? (isYear
                                ? const Color(0xFF20143F)
                                : const Color(0x54714CD6))
                            : Colors.transparent,
                        border: Border.all(
                          color: active
                              ? const Color(0xFF9B55FF)
                              : Colors.transparent,
                        ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF9B55FF)
                                      .withValues(alpha: isYear ? 0.45 : 0.24),
                                  blurRadius: isYear ? 10 : 8,
                                  spreadRadius: 0.4,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        entry.$2,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.8,
                              color: active
                                  ? Colors.white
                                  : const Color(0xD9B8AEE2),
                            ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _YearAverageHeroCard extends StatelessWidget {
  const _YearAverageHeroCard({required this.title, required this.average});

  final String title;
  final double? average;

  @override
  Widget build(BuildContext context) {
    final formatted = average == null ? '—' : average!.toStringAsFixed(2);
    final quality = _yearQuality(average);
    final isNoData = average == null;
    final isWarning = !isNoData && average! < 4.0;
    return Container(
      height: 142,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF100D25), Color(0xFF1B103A), Color(0xFF29124E)],
        ),
        border: Border.all(color: const Color(0xBF34275F), width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x15100C2A), blurRadius: 8, spreadRadius: 0.1),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            right: 8,
            top: 8,
            bottom: -8,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x3FA855FF),
                      blurRadius: 32,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: SizedBox(width: 142, height: 142),
              ),
            ),
          ),
          const _GradesHeroMascotDecor(),
          Positioned(
            right: -2,
            bottom: -22,
            child: IgnorePointer(
              child: SizedBox(
                width: 172,
                height: 178,
                child: Transform.translate(
                  offset: const Offset(0, 10),
                  child: Transform.scale(
                    scale: 1.28,
                    alignment: Alignment.bottomCenter,
                    child: const Image(
                      image: AssetImage('assets/images/grades_mascot.png'),
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      errorBuilder: _heroImageErrorBuilder,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            top: 14,
            bottom: 12,
            right: 148,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.2,
                      color: const Color(0xEAFFFFFF)),
                ),
                const SizedBox(height: 3),
                Text(
                  formatted,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900, fontSize: 32, height: 0.95),
                ),
                const SizedBox(height: 3),
                Container(
                  height: 32,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: isNoData
                        ? const Color(0x293B2A62)
                        : (isWarning
                            ? const Color(0xCC5A1D3B)
                            : quality.$2.withValues(alpha: 0.20)),
                    border: Border.all(color: quality.$2),
                  ),
                  child: Text(
                    quality.$1,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700, fontSize: 10.8),
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

class _GradesHeroMascotDecor extends StatelessWidget {
  const _GradesHeroMascotDecor();

  @override
  Widget build(BuildContext context) {
    const stars = <(double, double, double, Color)>[
      (6, 4, 4, Color(0xABFFFFFF)),
      (24, 10, 3, Color(0xA5C99DFF)),
      (42, 8, 2, Color(0x8C8F4CFF)),
      (10, 24, 5, Color(0xD0C99DFF)),
      (32, 30, 3, Color(0xB5FFFFFF)),
      (4, 44, 2, Color(0x8C8F4CFF)),
      (20, 55, 4, Color(0xBFFFFFFF)),
      (38, 62, 3, Color(0xA5C99DFF)),
    ];
    return Positioned(
      right: 134,
      top: 22,
      bottom: 10,
      child: IgnorePointer(
        child: SizedBox(
          width: 40,
          child: Stack(
            children: [
              for (final star in stars)
                Positioned(
                  right: star.$1,
                  top: star.$2,
                  child: Container(
                    width: star.$3,
                    height: star.$3,
                    decoration: BoxDecoration(
                      color: star.$4,
                      borderRadius: BorderRadius.circular(star.$3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _heroImageErrorBuilder(
  BuildContext _,
  Object __,
  StackTrace? ___,
) =>
    const SizedBox.shrink();

class _WeekTableGeometry {
  const _WeekTableGeometry({
    required this.subjectColumnWidth,
    required this.dayColumnWidth,
    required this.dayBadgeSize,
  });

  final double subjectColumnWidth;
  final double dayColumnWidth;
  final double dayBadgeSize;

  static _WeekTableGeometry fromWidth(double maxWidth, int dayCount) {
    final safeDayCount = dayCount.clamp(5, 7);
    final subjectTarget = switch (safeDayCount) {
      5 => maxWidth * 0.40,
      6 => maxWidth * 0.38,
      _ => maxWidth * 0.35,
    };
    final subjectWidth = subjectTarget.clamp(104.0, 132.0);
    final dayWidth =
        ((maxWidth - subjectWidth) / safeDayCount).clamp(22.0, 40.0);
    final badgeSize = (dayWidth - 4).clamp(20.0, 26.0);
    return _WeekTableGeometry(
      subjectColumnWidth: subjectWidth,
      dayColumnWidth: dayWidth,
      dayBadgeSize: badgeSize,
    );
  }
}

class _WeekTableRowData {
  const _WeekTableRowData({
    required this.subjectKey,
    required this.subjectName,
    required this.cells,
  });

  final String subjectKey;
  final String subjectName;
  final Map<int, _WeekCellDisplay> cells;
}

class _WeekCellDisplay {
  const _WeekCellDisplay({
    required this.marks,
    required this.attendance,
    required this.hasLesson,
    required this.showDot,
  });

  const _WeekCellDisplay.empty()
      : marks = const <String>[],
        attendance = null,
        hasLesson = false,
        showDot = false;

  final List<String> marks;
  final String? attendance;
  final bool hasLesson;
  final bool showDot;
}

class _WeekEmptyStateCard extends StatelessWidget {
  const _WeekEmptyStateCard({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('grades-week-empty-state'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14102D), Color(0xFF1B1239)],
        ),
        border: Border.all(color: const Color(0xB23A2A69)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xD9B8AEE2),
                  fontSize: 13,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _WeekTableHeader extends StatelessWidget {
  const _WeekTableHeader({
    required this.geometry,
    required this.weekdayDates,
    required this.selectedWeekday,
  });

  final _WeekTableGeometry geometry;
  final Map<int, String?> weekdayDates;
  final int selectedWeekday;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('grades-week-table-header'),
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2D68), Color(0xFF18285F)],
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: geometry.subjectColumnWidth,
            child: Text(
              'Предмет',
              key: const Key('grades-week-header-subject'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: Colors.white,
                  ),
            ),
          ),
          for (final weekday in [1, 2, 3, 4, 5, 6, 7])
            SizedBox(
              width: geometry.dayColumnWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: selectedWeekday == weekday
                      ? const Color(0x5B2A1953)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      key: Key('grades-week-header-day-$weekday'),
                      switch (weekday) {
                        1 => 'Пн',
                        2 => 'Вт',
                        3 => 'Ср',
                        4 => 'Чт',
                        5 => 'Пт',
                        6 => 'Сб',
                        7 => 'Вс',
                        _ => '',
                      },
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: weekday >= 6
                                ? const Color(0xFFFF7AA6)
                                : const Color(0xFFF0ECFF),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      key: Key('grades-week-header-date-$weekday'),
                      weekdayDates[weekday] ?? '',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xB3C5BDF0),
                            fontSize: 10.6,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekDaySelector extends StatelessWidget {
  const _WeekDaySelector({
    required this.selectedWeekday,
    required this.activeWeekdays,
    required this.weekdayDates,
    required this.onChanged,
  });

  final int selectedWeekday;
  final List<int> activeWeekdays;
  final Map<int, String?> weekdayDates;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('grades-week-day-selector'),
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFF12102B), Color(0xFF191335)],
        ),
        border: Border.all(color: const Color(0xA6302654)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < 7; index++) ...[
            if (index > 0) const SizedBox(width: 2),
            Expanded(
              child: _WeekDayChip(
                weekday: index + 1,
                selectedWeekday: selectedWeekday,
                isActiveInTable: activeWeekdays.contains(index + 1),
                dateText: (weekdayDates[index + 1] ?? '--').split('.').first,
                onTap: onChanged,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekDayChip extends StatelessWidget {
  const _WeekDayChip({
    required this.weekday,
    required this.selectedWeekday,
    required this.isActiveInTable,
    required this.dateText,
    required this.onTap,
  });

  final int weekday;
  final int selectedWeekday;
  final bool isActiveInTable;
  final String dateText;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final weekend = weekday >= 6;
    return GestureDetector(
      onTap: () => onTap(weekday),
      child: Container(
        key: Key(
            'grades-week-day-chip-$weekday-${selectedWeekday == weekday ? 'selected' : 'normal'}'),
        decoration: BoxDecoration(
          color: selectedWeekday == weekday
              ? const Color(0x9C463088)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: selectedWeekday == weekday
              ? Border.all(color: const Color(0xFFAE7CFF), width: 1.05)
              : null,
          boxShadow: selectedWeekday == weekday
              ? const [
                  BoxShadow(
                    color: Color(0x663D2B7A),
                    blurRadius: 9,
                    spreadRadius: 0.35,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              switch (weekday) {
                1 => 'Пн',
                2 => 'Вт',
                3 => 'Ср',
                4 => 'Чт',
                5 => 'Пт',
                6 => 'Сб',
                7 => 'Вс',
                _ => '',
              },
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: weekend
                        ? const Color(0xFFFF7AA6)
                        : (isActiveInTable
                            ? const Color(0xE6C4BCE8)
                            : const Color(0x9CB8AEE2)),
                    fontSize: 10.8,
                  ),
            ),
            const SizedBox(height: 1),
            Text(
              dateText,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 11.4,
                    color: weekend
                        ? const Color(0xFFFF7AA6)
                        : (isActiveInTable
                            ? Colors.white
                            : const Color(0x9CC4BCE8)),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekLegendCard extends StatelessWidget {
  const _WeekLegendCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('grades-week-legend'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          colors: [Color(0xFF13102C), Color(0xFF191335)],
        ),
        border: Border.all(color: const Color(0xA6302654)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: const [
            _WeekLegendItem(
                value: '5', label: 'Отлично', color: Color(0xFF66E36E)),
            SizedBox(width: 7),
            _WeekLegendItem(
                value: '4', label: 'Хорошо', color: Color(0xFFFF9F18)),
            SizedBox(width: 7),
            _WeekLegendItem(
                value: '3', label: 'Удовл.', color: Color(0xFFFF4B55)),
            SizedBox(width: 7),
            _WeekLegendItem(
                value: 'Н', label: 'Не был', color: Color(0xFF9A92BF)),
            SizedBox(width: 7),
            _WeekLegendItem(
                value: '•', label: 'Нет оценки', color: Color(0xFF8177A8)),
          ],
        ),
      ),
    );
  }
}

class _WeekLegendItem extends StatelessWidget {
  const _WeekLegendItem({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 9.6,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xD9B8AEE2),
                fontSize: 10.6,
              ),
        ),
      ],
    );
  }
}

class _WeekSummaryData {
  const _WeekSummaryData({
    required this.marksCount,
    required this.average,
    required this.attendancePercent,
  });
  final int marksCount;
  final double? average;
  final int? attendancePercent;
}

class _WeekSummaryCard extends StatelessWidget {
  const _WeekSummaryCard({
    required this.summary,
  });
  final _WeekSummaryData summary;

  @override
  Widget build(BuildContext context) {
    String marksLabel(int count) {
      final rem10 = count % 10;
      final rem100 = count % 100;
      if (rem10 == 1 && rem100 != 11) return 'оценка';
      if (rem10 >= 2 && rem10 <= 4 && (rem100 < 12 || rem100 > 14))
        return 'оценки';
      return 'оценок';
    }

    return Container(
      key: const Key('grades-week-summary-card'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFF13102C), Color(0xFF191335)],
        ),
        border: Border.all(color: const Color(0xA6302654)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [Color(0xFF6D49D7), Color(0xFF8A5DFF)],
              ),
            ),
            child:
                const Icon(Icons.star_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Итоги недели',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 13.8)),
              ],
            ),
          ),
          _WeekMetric(
              value: '${summary.marksCount}',
              label: marksLabel(summary.marksCount),
              valueColor: Colors.white),
          _weekDivider(),
          _WeekMetric(
              value: summary.average == null
                  ? '—'
                  : summary.average!.toStringAsFixed(1),
              label: 'средний балл',
              valueColor: summary.average == null
                  ? Colors.white
                  : const Color(0xFF66E36E)),
          _weekDivider(),
          _WeekMetric(
              value: summary.attendancePercent == null
                  ? '—'
                  : '${summary.attendancePercent}%',
              label: 'посещаемость',
              valueColor: summary.attendancePercent == null
                  ? Colors.white
                  : const Color(0xFFB985FF)),
        ],
      ),
    );
  }

  Widget _weekDivider() => Container(
      width: 1,
      height: 30,
      color: const Color(0x66302356),
      margin: const EdgeInsets.symmetric(horizontal: 6));
}

class _WeekMetric extends StatelessWidget {
  const _WeekMetric({
    required this.value,
    required this.label,
    required this.valueColor,
  });
  final String value;
  final String label;
  final Color valueColor;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 18.5,
                  color: valueColor)),
          Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: const Color(0xCCB8AEE2), fontSize: 10)),
        ],
      ),
    );
  }
}

class _WeekTableRow extends StatelessWidget {
  const _WeekTableRow({
    required this.row,
    required this.geometry,
    required this.visibleWeekdays,
    required this.showDivider,
  });

  final _WeekTableRowData row;
  final _WeekTableGeometry geometry;
  final List<int> visibleWeekdays;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('grades-week-row-${row.subjectKey}'),
      height: 56,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          SizedBox(
            width: geometry.subjectColumnWidth,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6D49D7), Color(0xFF8A5DFF)],
                    ),
                  ),
                  child: Icon(
                    _subjectIcon(row.subjectKey, row.subjectName),
                    size: 17,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        row.subjectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.2,
                            ),
                      ),
                      Text(
                        '${_markCountLabel(row)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: const Color(0xCCAAA0D2),
                              fontSize: 10.4,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (var index = 0; index < visibleWeekdays.length; index++)
                  Expanded(
                    child: Container(
                      key: Key(
                          'grades-week-column-${row.subjectKey}-${visibleWeekdays[index]}'),
                      child: Center(
                        child: _WeekTableCell(
                          cellKeyPrefix:
                              'grades-week-cell-${row.subjectKey}-${visibleWeekdays[index]}',
                          cell: row.cells[visibleWeekdays[index]] ??
                              const _WeekCellDisplay.empty(),
                          badgeSize: geometry.dayBadgeSize,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _markCountLabel(_WeekTableRowData row) {
    var count = 0;
    for (final cell in row.cells.values) {
      count += cell.marks.length;
    }
    if (count == 0) return '0 оценок';
    final rem10 = count % 10;
    final rem100 = count % 100;
    if (rem10 == 1 && rem100 != 11) return '$count оценка';
    if (rem10 >= 2 && rem10 <= 4 && (rem100 < 12 || rem100 > 14)) {
      return '$count оценки';
    }
    return '$count оценок';
  }
}

class _WeekTableCell extends StatelessWidget {
  const _WeekTableCell({
    required this.cell,
    required this.cellKeyPrefix,
    required this.badgeSize,
  });

  final _WeekCellDisplay cell;
  final String cellKeyPrefix;
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    if (cell.marks.isNotEmpty) {
      final marks = cell.marks.take(2).toList(growable: false);
      final hidden = cell.marks.length - marks.length;
      if (marks.length == 1) {
        return _WeekMarkBadge(
          key: Key('$cellKeyPrefix-mark-1'),
          value: marks.first,
          size: badgeSize,
        );
      }
      return SizedBox(
        key: Key('$cellKeyPrefix-marks'),
        height: badgeSize + 8,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 2,
              runSpacing: 2,
              children: marks
                  .asMap()
                  .entries
                  .map<Widget>((entry) => _WeekMarkBadge(
                        key: Key('$cellKeyPrefix-mark-${entry.key + 1}'),
                        value: entry.value,
                        compact: true,
                        size: badgeSize - 4,
                      ))
                  .toList(growable: false),
            ),
            if (hidden > 0)
              Text(
                '+$hidden',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      color: const Color(0xCCB8AEE2),
                    ),
              )
          ],
        ),
      );
    }
    if (cell.attendance != null) {
      return _WeekAttendanceBadge(
        key: Key('$cellKeyPrefix-attendance'),
        code: cell.attendance!,
        size: badgeSize,
      );
    }
    if (cell.showDot) {
      return Text(
        key: Key('$cellKeyPrefix-dot'),
        '•',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xB38177A8),
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
            ),
      );
    }
    return SizedBox(width: badgeSize, height: badgeSize);
  }
}

class _WeekMarkBadge extends StatelessWidget {
  const _WeekMarkBadge({
    super.key,
    required this.value,
    this.compact = false,
    this.size = 24,
  });

  final String value;
  final bool compact;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = value.contains('/')
        ? _gradePaletteFromFraction(value)
        : _gradePaletteFromMark(value);
    final clean = value.trim();
    return Container(
      width: compact ? (size * 0.8) : size,
      height: compact ? (size * 0.8) : size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.fill,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Text(
        clean,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: compact ? 9 : 11.5,
              color: Colors.white,
              height: 1.0,
            ),
      ),
    );
  }
}

class _WeekAttendanceBadge extends StatelessWidget {
  const _WeekAttendanceBadge({
    super.key,
    required this.code,
    required this.size,
  });

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = _attendancePalette(code);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.fill,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        code,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.text,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
      ),
    );
  }
}

class _TotalsGridGeometry {
  const _TotalsGridGeometry(
      {required this.gradeColumnWidth, required this.chevronWidth});

  final double gradeColumnWidth;
  final double chevronWidth;

  static _TotalsGridGeometry fromWidth(double maxWidth) {
    final gradeWidth = maxWidth < 360 ? 22.0 : 26.0;
    return _TotalsGridGeometry(
        gradeColumnWidth: gradeWidth, chevronWidth: 18.0);
  }
}

class _TotalsHeaderRow extends StatelessWidget {
  const _TotalsHeaderRow({required this.geometry});

  final _TotalsGridGeometry geometry;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFFB8B0E8),
          fontWeight: FontWeight.w800,
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
    required this.subjectKey,
    required this.subjectName,
    required this.quarterValues,
    required this.yearValue,
    required this.selectedTerm,
    required this.expanded,
    this.showChevron = true,
  });

  final _TotalsGridGeometry geometry;
  final String subjectKey;
  final String subjectName;
  final List<String> quarterValues;
  final String yearValue;
  final int? selectedTerm;
  final bool expanded;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final displayValue = selectedTerm == null
        ? _yearOnlyDisplay(yearValue)
        : _displayGradeOrDash(quarterValues[selectedTerm! - 1]);
    final valueColor = _gradePaletteFromMark(displayValue).fill;
    final isDash = _isDashValue(displayValue);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
                colors: [Color(0xFF6D49D7), Color(0xFF8A5DFF)]),
            border: Border.all(color: const Color(0x80C7A1FF)),
          ),
          child: Icon(_subjectIcon(subjectKey, subjectName),
              size: 19, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            subjectName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          displayValue,
          key: Key('grades-totals-collapsed-value-$subjectKey'),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18.5,
                color: isDash ? const Color(0xFF9B8FB8) : valueColor,
              ),
        ),
        if (showChevron) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: geometry.chevronWidth,
            child: Icon(
              key: Key('grades-totals-chevron-$subjectKey'),
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 21,
              color: const Color(0xFFD7CCFF),
            ),
          ),
        ],
      ],
    );
  }
}

class _TermHeaderRow extends StatelessWidget {
  const _TermHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: const Color(0xD9B8B0E8),
          fontWeight: FontWeight.w700,
          fontSize: 13,
        );
    return Row(
      children: [
        Expanded(child: Text('Предмет', style: style)),
        Text('Оценка', style: style),
        const SizedBox(width: 20),
      ],
    );
  }
}

class _QuarterDetailRow extends StatelessWidget {
  const _QuarterDetailRow({required this.marks});

  final _QuarterMarks marks;

  @override
  Widget build(BuildContext context) {
    final sorSlots = List<_ValueMood>.generate(
      3,
      (i) => i < marks.sor.length
          ? marks.sor[i]
          : const _ValueMood(value: '-', mood: ''),
    );
    final sochSlot = marks.soch.isNotEmpty
        ? marks.soch.first
        : const _ValueMood(value: '-', mood: '');

    return Row(
      children: [
        Expanded(
          child: _ExpandedWorkTile(
            key: const Key('grades_totals_expanded_work_tile_sor_1'),
            label: 'СОР',
            vm: sorSlots[0],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _ExpandedWorkTile(
            key: const Key('grades_totals_expanded_work_tile_sor_2'),
            label: 'СОР',
            vm: sorSlots[1],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _ExpandedWorkTile(
            key: const Key('grades_totals_expanded_work_tile_sor_3'),
            label: 'СОР',
            vm: sorSlots[2],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _ExpandedWorkTile(
            key: const Key('grades_totals_expanded_work_tile_soch'),
            label: 'СОЧ',
            vm: sochSlot,
          ),
        ),
      ],
    );
  }
}

class _YearSummaryDetail extends StatelessWidget {
  const _YearSummaryDetail({required this.termMap});

  final Map<int, _QuarterMarks> termMap;

  @override
  Widget build(BuildContext context) {
    _ValueMood sorAt(int term) {
      final mark = termMap[term];
      if (mark == null || mark.sor.isEmpty) {
        return const _ValueMood(value: '-', mood: '');
      }
      return mark.sor.first;
    }

    _ValueMood sochAt(int term) {
      final mark = termMap[term];
      if (mark == null || mark.soch.isEmpty) {
        return const _ValueMood(value: '-', mood: '');
      }
      return mark.soch.first;
    }

    Widget section(String title, _ValueMood Function(int term) pickValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFBDB4E7),
                ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final term in [1, 2, 3, 4]) ...[
                if (term != 1) const SizedBox(width: 8),
                Expanded(
                  child: _ExpandedWorkTile(
                    label: '$term',
                    vm: pickValue(term),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        section('СОР', sorAt),
        const SizedBox(height: 8),
        section('СОЧ', sochAt),
      ],
    );
  }
}

class _ExpandedWorkTile extends StatelessWidget {
  const _ExpandedWorkTile({
    super.key,
    required this.label,
    required this.vm,
  });

  final String label;
  final _ValueMood vm;

  @override
  Widget build(BuildContext context) {
    final normalized = vm.value.trim().isEmpty ? '-' : vm.value.trim();
    final palette = normalized == '-'
        ? _mutedPalette()
        : _paletteForSummative(mood: vm.mood, value: normalized);
    final muted = normalized == '-' || palette.muted;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF241544),
        borderRadius: BorderRadius.circular(10.5),
        border: Border.all(color: const Color(0xD93D2F70)),
        boxShadow: const [BoxShadow(color: Color(0x0AFFFFFF), blurRadius: 2)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 0.2,
                  color: const Color(0xFFB8AEE2),
                ),
          ),
          const SizedBox(height: 3),
          Text(
            normalized,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 15.6,
                  fontWeight: muted ? FontWeight.w800 : FontWeight.w900,
                  height: 1.0,
                  color: muted ? const Color(0xFF8177A8) : palette.fill,
                ),
          ),
        ],
      ),
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
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: palette.fill,
        border: Border.all(color: palette.border),
      ),
      child: Text(
        normalized,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isMuted ? palette.text : Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge(
      {required this.value, required this.palette, this.compact = false});

  final String value;
  final _GradePalette palette;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim().isEmpty ? '-' : value.trim();
    final isMuted = normalized == '-' || palette.muted;
    return Container(
      constraints: BoxConstraints(minWidth: compact ? 20 : 34),
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        color: palette.fill,
        border: Border.all(color: palette.border),
      ),
      child: Text(
        normalized,
        maxLines: 1,
        softWrap: false,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isMuted ? palette.text : Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
      ),
    );
  }
}

class _GradePalette {
  const _GradePalette(
      {required this.fill,
      required this.border,
      required this.text,
      this.muted = false});

  final Color fill;
  final Color border;
  final Color text;
  final bool muted;
}

(String, Color) _yearQuality(double? average) {
  if (average == null) return ('Нет данных', const Color(0xFF8F73C9));
  if (average >= 4.5) return ('Отлично', const Color(0xFFB985FF));
  if (average >= 4.0) return ('Хорошо', const Color(0xFFB777FF));
  return ('Нужно подтянуть', const Color(0xCCFF4B8B));
}

IconData _subjectIcon(String key, String name) {
  final source = '$key $name'.toLowerCase();
  if (source.contains('алгеб') || source.contains('мат'))
    return Icons.functions_rounded;
  if (source.contains('СЂСѓСЃ') ||
      source.contains('қаз') ||
      source.contains('каз') ||
      source.contains('язык')) return Icons.text_fields_rounded;
  if (source.contains('физ')) return Icons.bubble_chart_rounded;
  if (source.contains('информ')) return Icons.computer_rounded;
  if (source.contains('истор')) return Icons.menu_book_rounded;
  if (source.contains('биол')) return Icons.eco_rounded;
  if (source.contains('англ') || source.contains('english'))
    return Icons.translate_rounded;
  return Icons.school_rounded;
}

String _yearOnlyDisplay(String yearValue) {
  return _displayGradeOrDash(yearValue);
}

String _displayGradeOrDash(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty || normalized == '-') return '—';
  return normalized;
}

bool _isDashValue(String value) {
  final normalized = value.trim();
  return normalized.isEmpty || normalized == '-' || normalized == '—';
}

_GradePalette _paletteForSummative(
    {required String mood, required String value}) {
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
    if (RegExp(r'^\d+$').hasMatch(value) ||
        RegExp(r'^\d+\s*/\s*\d+$').hasMatch(value)) {
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
  if (good.contains(m)) return _solidPalette(const Color(0xFF66E36E));
  if (neutral.contains(m)) return _solidPalette(const Color(0xFFFF9F18));
  if (bad.contains(m)) return _solidPalette(const Color(0xFFFF4B55));
  return null;
}

_GradePalette _gradePaletteFromMark(String raw) {
  final value = int.tryParse(raw.trim());
  if (value == null) return _mutedPalette();

  if (value <= 5) {
    if (value == 5) return _solidPalette(const Color(0xFF66E36E));
    if (value == 4) return _solidPalette(const Color(0xFFFF9F18));
    if (value == 3) return _solidPalette(const Color(0xFFFF4B55));
    return _solidPalette(const Color(0xFFFF4B55));
  }

  if (value >= 9) return _solidPalette(const Color(0xFF66E36E));
  if (value >= 7) return _solidPalette(const Color(0xFFFF9F18));
  if (value >= 5) return _solidPalette(const Color(0xFFFF9F18));
  return _solidPalette(const Color(0xFFFF4B55));
}

_GradePalette _gradePaletteFromFraction(String raw) {
  final parts = raw.split('/');
  if (parts.length != 2) return _gradePaletteFromMark(raw);

  final value = double.tryParse(parts[0].trim());
  final maxValue = double.tryParse(parts[1].trim());
  if (value == null || maxValue == null || maxValue <= 0)
    return _mutedPalette();

  final percent = value / maxValue;
  if (percent >= 0.8) return _solidPalette(const Color(0xFF66E36E));
  if (percent >= 0.6) return _solidPalette(const Color(0xFFFF9F18));
  return _solidPalette(const Color(0xFFFF4B55));
}

_GradePalette _attendancePalette(String code) {
  switch (code) {
    case 'О':
    case 'Б':
    case 'Н':
      return const _GradePalette(
        fill: Color(0xFF8E88AA),
        border: Color(0xFFC0BADB),
        text: Colors.white,
      );
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
  const muted = Color(0xFF8177A8);
  return _GradePalette(
    fill: Color(0x33211742),
    border: Color(0xD94A3479),
    text: muted,
    muted: true,
  );
}
