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
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: _to,
      helpText: '시작 날짜',
    );
    if (picked == null || picked == _from) return;
    setState(() => _from = picked);
    _load();
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now(),
      helpText: '끝 날짜',
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
