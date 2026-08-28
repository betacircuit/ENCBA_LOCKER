part of '../locker_shell.dart';

String _attendanceRangeLabel(DateTime from, DateTime to) =>
    '${from.year}.${from.month}.${from.day} ~ ${to.year}.${to.month}.${to.day}';

class AttendanceReportScreen extends ConsumerStatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  ConsumerState<AttendanceReportScreen> createState() =>
      _AttendanceReportScreenState();
}

class _AttendanceReportScreenState
    extends ConsumerState<AttendanceReportScreen> {
  bool _freshmenOnly = false;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  List<AttendanceReportRow> _rows = const [];

  /// 기본 범위는 직전 학기 시작(방학 포함)부터 지금까지. 지난 일정도
  /// 응답 기록이 남아 있는 한 언제든 이 화면에서 다시 집계할 수 있다.
  DateTime _from = previousSemesterStart(DateTime.now());
  DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _pickFrom() async {
    final picked = await _pickSemesterAwareDate(
      context: context,
      initialDate: _from,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: _to,
      title: '시작 날짜',
    );
    if (picked == null || picked == _from) return;
    setState(() => _from = picked);
    _load();
  }

  Future<void> _pickTo() async {
    final picked = await _pickSemesterAwareDate(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now(),
      title: '끝 날짜',
    );
    if (picked == null || picked == _to) return;
    setState(() => _to = picked.add(const Duration(days: 1)));
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await ref
          .read(lockerControllerProvider.notifier)
          .loadAttendanceReport(
            from: _from,
            to: _to,
            freshmenOnly: _freshmenOnly,
          );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA attendance sheet load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '출결 정보를 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _export() async {
    if (_exporting || _rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final saved = await AttendanceReportService().export(
        rows: _rows,
        freshmenOnly: _freshmenOnly,
        year: DateTime.now().year,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(saved ? '출결 관리표를 저장했습니다.' : '파일 저장을 취소했습니다.')),
        );
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA attendance sheet export failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('출결 관리표를 저장하지 못했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdminister =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    final summaries = _summaries(_rows);
    final eventCount = _rows.map((row) => row.eventId).toSet().length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('출결 정리 시트'),
        actions: [
          if (canAdminister)
            IconButton(
              tooltip: '엑셀로 저장',
              onPressed: _exporting || _rows.isEmpty ? null : _export,
              icon: _exporting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
            ),
        ],
      ),
      body: !canAdminister
          ? const Center(child: Text('관리자만 확인할 수 있습니다.'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('전체')),
                          ButtonSegment(value: true, label: Text('신입생')),
                        ],
                        selected: {_freshmenOnly},
                        onSelectionChanged: (selection) {
                          final next = selection.first;
                          if (next == _freshmenOnly) return;
                          setState(() => _freshmenOnly = next);
                          _load();
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickFrom,
                              icon: const Icon(Icons.date_range_outlined, size: 18),
                              label: Text(
                                '${_from.year}.${_from.month}.${_from.day}',
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text('~'),
                          ),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickTo,
                              icon: const Icon(Icons.date_range_outlined, size: 18),
                              label: Text(
                                '${_to.year}.${_to.month}.${_to.day}',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_attendanceRangeLabel(_from, _to)} · 일정 $eventCount개 · 인원 ${summaries.length}명',
                        style: const TextStyle(color: EncbaColors.muted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: switch ((_loading, _error, summaries.isEmpty)) {
                    (true, _, _) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    (false, final error?, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _load,
                            child: const Text('다시 불러오기'),
                          ),
                        ],
                      ),
                    ),
                    (false, null, true) => const Center(
                      child: Text('정리할 출결 정보가 없습니다.'),
                    ),
                    _ => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 22,
                          columns: const [
                            DataColumn(label: Text('학번')),
                            DataColumn(label: Text('이름')),
                            DataColumn(label: Text('참석'), numeric: true),
                            DataColumn(label: Text('불참'), numeric: true),
                            DataColumn(label: Text('미정/미응답'), numeric: true),
                            DataColumn(label: Text('참석률'), numeric: true),
                          ],
                          rows: summaries
                              .map(
                                (item) => DataRow(
                                  cells: [
                                    DataCell(
                                      Text(item.studentYear?.toString() ?? '-'),
                                    ),
                                    DataCell(Text(item.displayName)),
                                    DataCell(Text('${item.attending}')),
                                    DataCell(Text('${item.absent}')),
                                    DataCell(Text('${item.undecided}')),
                                    DataCell(Text('${item.rate}%')),
                                  ],
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ),
                  },
                ),
              ],
            ),
    );
  }

  List<_AttendanceSummary> _summaries(List<AttendanceReportRow> rows) {
    final byMember = <String, List<AttendanceReportRow>>{};
    for (final row in rows) {
      byMember.putIfAbsent(row.directoryId, () => []).add(row);
    }
    // 동명이인이 있으면 이름 옆에 학번을 붙여 두 사람을 구분하게 한다.
    final nameCounts = <String, int>{};
    for (final row in rows) {
      nameCounts[row.memberName] = (nameCounts[row.memberName] ?? 0) + 1;
    }
    final result =
        byMember.values
            .map((memberRows) {
              final first = memberRows.first;
              final attending = memberRows
                  .where((row) => row.choice == '참석')
                  .length;
              final absent = memberRows
                  .where((row) => row.choice == '불참')
                  .length;
              final undecided = memberRows.length - attending - absent;
              final duplicate = (nameCounts[first.memberName] ?? 0) > 1;
              return _AttendanceSummary(
                name: first.memberName,
                displayName:
                    duplicate && first.studentYear != null
                        ? '${first.memberName} (${first.studentYear}학번)'
                        : first.memberName,
                studentYear: first.studentYear,
                attending: attending,
                absent: absent,
                undecided: undecided,
                rate: memberRows.isEmpty
                    ? 0
                    : ((attending / memberRows.length) * 100).round(),
              );
            })
            .toList(growable: false)
          ..sort((a, b) {
            final byYear = (a.studentYear ?? 999).compareTo(
              b.studentYear ?? 999,
            );
            return byYear != 0 ? byYear : a.name.compareTo(b.name);
          });
    return result;
  }
}

class _AttendanceSummary {
  const _AttendanceSummary({
    required this.name,
    required this.displayName,
    required this.studentYear,
    required this.attending,
    required this.absent,
    required this.undecided,
    required this.rate,
  });

  final String name;

  /// 동명이인일 때는 "이름 (학번)" 형태로 표시된다.
  final String displayName;
  final int? studentYear;
  final int attending;
  final int absent;
  final int undecided;
  final int rate;
}

/// 학기 구분. 방학도 하나의 학기로 세어, 캘린더에 시작일을 모두 찍는다.
enum AcademicTerm {
  spring('1학기', 3, 1),
  summer('여름학기', 6, 16),
  fall('2학기', 9, 1),
  winter('겨울학기', 12, 15);

  const AcademicTerm(this.label, this.startMonth, this.startDay);

  final String label;
  final int startMonth;
  final int startDay;

  DateTime startIn(int year) => DateTime(year, startMonth, startDay);
}

/// [year]년에 시작하는 네 학기의 시작일.
List<({AcademicTerm term, DateTime start})> academicTermStarts(int year) => [
  for (final term in AcademicTerm.values)
    (term: term, start: term.startIn(year)),
];

/// [date]가 속한 학기와 그 시작일. 1~2월은 지난해 겨울학기의 연장이다.
({AcademicTerm term, DateTime start}) academicTermOf(DateTime date) {
  final day = DateUtils.dateOnly(date);
  final candidates =
      [
        ...academicTermStarts(day.year - 1),
        ...academicTermStarts(day.year),
      ].where((item) => !item.start.isAfter(day)).toList();
  return candidates.last;
}

/// 출결 정리 시트의 기본 범위가 시작하는 날. 캘린더에서 이 날을 따로
/// 강조해 "직전학기가 여기서 시작한다"는 걸 눈으로 확인할 수 있게 한다.
DateTime attendanceRangeAnchor(DateTime now) => previousSemesterStart(now);

/// 학기 시작을 표시해 주는 날짜 선택 시트. Material 기본 달력은 특정
/// 날짜에 표식을 달 수 없어서, 출결 시트에서만 쓰는 달력을 따로 그린다.
Future<DateTime?> _pickSemesterAwareDate({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required String title,
}) => showModalBottomSheet<DateTime>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => _SemesterDatePickerSheet(
    title: title,
    initialDate: initialDate,
    firstDate: DateUtils.dateOnly(firstDate),
    lastDate: DateUtils.dateOnly(lastDate),
  ),
);

class _SemesterDatePickerSheet extends StatefulWidget {
  const _SemesterDatePickerSheet({
    required this.title,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final String title;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_SemesterDatePickerSheet> createState() =>
      _SemesterDatePickerSheetState();
}

class _SemesterDatePickerSheetState extends State<_SemesterDatePickerSheet> {
  late DateTime _selected = DateUtils.dateOnly(widget.initialDate);
  late DateTime _visibleMonth = DateTime(_selected.year, _selected.month);

  bool _selectable(DateTime day) =>
      !day.isBefore(widget.firstDate) && !day.isAfter(widget.lastDate);

  @override
  Widget build(BuildContext context) {
    final anchor = attendanceRangeAnchor(DateTime.now());
    final currentTerm = academicTermOf(_visibleMonth);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '보고 있는 달은 ${currentTerm.term.label} 기간입니다. '
              '학기가 시작하는 날에는 색 띠와 이름을 붙여 두었습니다.',
              style: const TextStyle(
                color: EncbaColors.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            _SemesterLegend(anchor: anchor),
            const SizedBox(height: 12),
            _SemesterCalendar(
              visibleMonth: _visibleMonth,
              selected: _selected,
              anchor: anchor,
              isSelectable: _selectable,
              onMonthChanged: (month) => setState(() => _visibleMonth = month),
              onSelected: (day) => setState(() => _selected = day),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _selectable(_selected)
                  ? () => Navigator.pop(context, _selected)
                  : null,
              child: Text(
                '${_selected.year}.${_selected.month}.${_selected.day} 선택',
              ),
            ),
            if (_selectable(anchor)) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _selected = anchor;
                  _visibleMonth = DateTime(anchor.year, anchor.month);
                }),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: Text(
                  '직전학기 시작(${anchor.year}.${anchor.month}.${anchor.day})으로',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SemesterLegend extends StatelessWidget {
  const _SemesterLegend({required this.anchor});

  final DateTime anchor;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      for (final term in AcademicTerm.values)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _termColor(term),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '${term.label} ${term.startMonth}.${term.startDay}',
              style: const TextStyle(fontSize: 11, color: EncbaColors.muted),
            ),
          ],
        ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag_rounded, size: 12, color: EncbaColors.navy),
          const SizedBox(width: 4),
          Text(
            '직전학기 시작 ${anchor.year}.${anchor.month}.${anchor.day}',
            style: const TextStyle(
              fontSize: 11,
              color: EncbaColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ],
  );
}

Color _termColor(AcademicTerm term) => switch (term) {
  AcademicTerm.spring => EncbaColors.attending,
  AcademicTerm.summer => EncbaColors.late,
  AcademicTerm.fall => EncbaColors.snuBlue,
  AcademicTerm.winter => EncbaColors.undecided,
};

class _SemesterCalendar extends StatelessWidget {
  const _SemesterCalendar({
    required this.visibleMonth,
    required this.selected,
    required this.anchor,
    required this.isSelectable,
    required this.onMonthChanged,
    required this.onSelected,
  });

  final DateTime visibleMonth;
  final DateTime selected;
  final DateTime anchor;
  final bool Function(DateTime day) isSelectable;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(visibleMonth.year, visibleMonth.month);
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final leading = first.weekday - 1;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final termStartsThisMonth = <int, AcademicTerm>{
      for (final term in AcademicTerm.values)
        if (term.startMonth == visibleMonth.month) term.startDay: term,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EncbaColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '이전 달',
                onPressed: () => onMonthChanged(
                  DateTime(visibleMonth.year, visibleMonth.month - 1),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${visibleMonth.year}년 ${visibleMonth.month}월',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '다음 달',
                onPressed: () => onMonthChanged(
                  DateTime(visibleMonth.year, visibleMonth.month + 1),
                ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Row(
            children: [
              for (final label in ['월', '화', '수', '목', '금', '토', '일'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: EncbaColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cellCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 52,
            ),
            itemBuilder: (context, index) {
              final dayNumber = index - leading + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const SizedBox.shrink();
              }
              final day = DateTime(
                visibleMonth.year,
                visibleMonth.month,
                dayNumber,
              );
              final term = termStartsThisMonth[dayNumber];
              final isAnchor = DateUtils.isSameDay(day, anchor);
              final isSelected = DateUtils.isSameDay(day, selected);
              final enabled = isSelectable(day);
              return Semantics(
                button: true,
                selected: isSelected,
                enabled: enabled,
                label: [
                  '$dayNumber일',
                  if (term != null) '${term.label} 시작',
                  if (isAnchor) '직전학기 시작',
                ].join(', '),
                excludeSemantics: true,
                child: InkWell(
                  onTap: enabled ? () => onSelected(day) : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: isSelected ? EncbaColors.navy : Colors.transparent,
                      border: isAnchor && !isSelected
                          ? Border.all(color: EncbaColors.navy, width: 1.5)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNumber',
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? Colors.white
                                : enabled
                                ? EncbaColors.ink
                                : EncbaColors.muted.withValues(alpha: .45),
                            fontWeight: term != null || isAnchor
                                ? FontWeight.w800
                                : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (term != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : _termColor(term),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              term.label,
                              style: TextStyle(
                                fontSize: 8,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? EncbaColors.navy
                                    : Colors.white,
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
