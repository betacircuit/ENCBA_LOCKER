part of '../locker_shell.dart';

/// 내 응답 한 건을 요약해 보여주기 위한 값.
class _MyAttendanceEntry {
  const _MyAttendanceEntry({
    required this.event,
    required this.choice,
    required this.respondedAt,
    this.absenceReason,
  });

  final LockerEvent event;
  final String choice;
  final DateTime respondedAt;
  final String? absenceReason;

  /// 참석/불참처럼 확정된 응답인지. 미정은 통계에서 분모로 쓰지 않는다.
  bool get isDecided => choice == '참석' || choice == '불참';
}

/// 종류·요일·월처럼 한 기준으로 묶은 참석 집계.
class _MyAttendanceBucket {
  _MyAttendanceBucket(this.label);

  final String label;
  int attend = 0;
  int absent = 0;
  int undecided = 0;

  int get decided => attend + absent;
  int get total => decided + undecided;

  /// 확정 응답이 없으면 참석률을 계산하지 않는다(0%로 속이지 않기 위해).
  double? get rate => decided == 0 ? null : attend / decided;
}

/// 내 출결 응답을 여러 각도로 정리한 결과.
class _MyAttendanceStats {
  _MyAttendanceStats({
    required this.entries,
    required this.attend,
    required this.absent,
    required this.undecided,
    required this.byKind,
    required this.byWeekday,
    required this.byMonth,
    required this.reasons,
    required this.currentStreak,
    required this.bestStreak,
  });

  /// 최신 일정이 앞에 오도록 정렬된 응답 목록.
  final List<_MyAttendanceEntry> entries;
  final int attend;
  final int absent;
  final int undecided;

  /// 응답이 있는 일정 종류만, 참석률이 높은 순.
  final List<_MyAttendanceBucket> byKind;

  /// 월요일부터 일요일까지 고정 순서.
  final List<_MyAttendanceBucket> byWeekday;

  /// 오래된 달이 앞에 오는 월별 집계.
  final List<_MyAttendanceBucket> byMonth;

  /// 불참 사유별 건수(많은 순).
  final List<MapEntry<String, int>> reasons;

  /// 최근 응답부터 끊기지 않고 이어진 참석 횟수.
  final int currentStreak;

  /// 지금까지의 최고 연속 참석 횟수.
  final int bestStreak;

  int get responded => attend + absent + undecided;
  int get decided => attend + absent;
  double? get rate => decided == 0 ? null : attend / decided;

  /// 최신 [count]건의 확정 응답만 본 참석률과 실제 표본 수.
  ({int decided, double? rate}) recent(int count) {
    var seen = 0;
    var attended = 0;
    for (final entry in entries) {
      if (!entry.isDecided) continue;
      if (entry.choice == '참석') attended++;
      seen++;
      if (seen == count) break;
    }
    return (decided: seen, rate: seen == 0 ? null : attended / seen);
  }
}

/// 로그인한 사용자의 출결 응답을 모아 통계로 계산한다.
///
/// profileId는 Supabase profiles.id(=auth uid)와 같으므로 현재 사용자
/// id와 직접 비교한다. 응답이 없는 일정은 집계에서 뺀다.
_MyAttendanceStats _computeMyAttendance(
  List<LockerEvent> events,
  Map<String, List<AttendanceResponse>> attendance,
  String userId,
) {
  final entries = <_MyAttendanceEntry>[];
  var attend = 0;
  var absent = 0;
  var undecided = 0;
  for (final event in events) {
    final mine = attendance[event.id]
        ?.where((response) => response.profileId == userId)
        .firstOrNull;
    if (mine == null) continue;
    switch (mine.choice) {
      case '참석':
        attend++;
      case '불참':
        absent++;
      default:
        undecided++;
    }
    entries.add(
      _MyAttendanceEntry(
        event: event,
        choice: mine.choice,
        respondedAt: mine.respondedAt,
        absenceReason: mine.absenceReason,
      ),
    );
  }
  entries.sort((a, b) => b.event.start.compareTo(a.event.start));

  final kindBuckets = <EventKind, _MyAttendanceBucket>{};
  final weekdayBuckets = [
    for (final day in const ['월', '화', '수', '목', '금', '토', '일'])
      _MyAttendanceBucket(day),
  ];
  // 연·월을 하나의 정수 키로 눌러 담아 해가 바뀌어도 순서가 섞이지 않게 한다.
  final monthBuckets = <int, _MyAttendanceBucket>{};
  final reasonCounts = <String, int>{};

  for (final entry in entries) {
    final start = entry.event.start;
    final kind = kindBuckets.putIfAbsent(
      entry.event.kind,
      () => _MyAttendanceBucket(entry.event.kind.label),
    );
    final weekday = weekdayBuckets[start.weekday - 1];
    final month = monthBuckets.putIfAbsent(
      start.year * 12 + start.month,
      () => _MyAttendanceBucket('${start.year % 100}.${start.month}'),
    );
    for (final bucket in [kind, weekday, month]) {
      switch (entry.choice) {
        case '참석':
          bucket.attend++;
        case '불참':
          bucket.absent++;
        default:
          bucket.undecided++;
      }
    }
    if (entry.choice == '불참') {
      final raw = entry.absenceReason?.trim() ?? '';
      final label = raw.isEmpty
          ? '사유 미기재'
          : (absenceReasonPresetOf(raw) ?? '직접 입력');
      reasonCounts[label] = (reasonCounts[label] ?? 0) + 1;
    }
  }

  // 확정 응답만 오래된 순으로 훑어 연속 참석 기록을 센다.
  final decidedOldestFirst = entries.where((e) => e.isDecided).toList().reversed;
  var bestStreak = 0;
  var running = 0;
  for (final entry in decidedOldestFirst) {
    running = entry.choice == '참석' ? running + 1 : 0;
    if (running > bestStreak) bestStreak = running;
  }
  final currentStreak = running;

  final kinds = kindBuckets.values.toList()
    ..sort((a, b) {
      final rateA = a.rate ?? -1;
      final rateB = b.rate ?? -1;
      if (rateA != rateB) return rateB.compareTo(rateA);
      return b.total.compareTo(a.total);
    });
  final months = monthBuckets.keys.toList()..sort();
  final reasons = reasonCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return _MyAttendanceStats(
    entries: entries,
    attend: attend,
    absent: absent,
    undecided: undecided,
    byKind: kinds,
    byWeekday: weekdayBuckets.where((bucket) => bucket.total > 0).toList(),
    byMonth: [for (final key in months) monthBuckets[key]!],
    reasons: reasons,
    currentStreak: currentStreak,
    bestStreak: bestStreak,
  );
}

String _ratePercent(double? rate) =>
    rate == null ? '-' : '${(rate * 100).round()}%';

Future<void> _showMyAttendance(BuildContext context, WidgetRef ref) async {
  final user = ref.read(authControllerProvider).user!;
  final state = ref.read(lockerControllerProvider);
  final stats = _computeMyAttendance(
    state.eventsState.events,
    state.eventsState.eventAttendance,
    user.id ?? '',
  );
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * .86),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _MyAttendanceReport(stats: stats),
          ),
        ),
      );
    },
  );
}

/// 내 출결 통계 본문. 표본이 적을 때는 수치를 단정적으로 보여주지 않는다.
class _MyAttendanceReport extends StatelessWidget {
  const _MyAttendanceReport({required this.stats});

  final _MyAttendanceStats stats;

  @override
  Widget build(BuildContext context) {
    final recent5 = stats.recent(5);
    final recent10 = stats.recent(10);
    final months = stats.byMonth.length > 6
        ? stats.byMonth.sublist(stats.byMonth.length - 6)
        : stats.byMonth;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('내 출결 통계', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          stats.responded == 0
              ? '아직 응답한 일정이 없습니다.'
              : '응답 ${stats.responded}건 · 확정 ${stats.decided}건 · '
                    '참석률 ${_ratePercent(stats.rate)}',
          style: const TextStyle(color: EncbaColors.muted),
        ),
        if (stats.responded == 0) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('일정 카드의 참석 버튼으로 응답하면 여기에 기록됩니다.')),
          ),
        ] else ...[
          if (stats.decided < 3) ...[
            const SizedBox(height: 12),
            _MyAttendanceNotice(
              '확정 응답이 ${0}건뿐이라 아래 수치는 아직 경향이라고 부르기 어렵습니다. 참고만 해 주세요.',
              count: stats.decided,
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat(value: '${stats.attend}', label: '참석'),
                  const _Rule(),
                  _Stat(value: '${stats.absent}', label: '불참'),
                  const _Rule(),
                  _Stat(value: '${stats.undecided}', label: '미정'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _MyAttendanceSection('최근 흐름'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat(value: _ratePercent(stats.rate), label: '전체'),
                  const _Rule(),
                  _Stat(
                    value: _ratePercent(recent10.rate),
                    label: '최근 ${recent10.decided}회',
                  ),
                  const _Rule(),
                  _Stat(
                    value: _ratePercent(recent5.rate),
                    label: '최근 ${recent5.decided}회',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MyAttendanceHighlight(
                  icon: Icons.local_fire_department_rounded,
                  value: '${stats.currentStreak}회',
                  label: '현재 연속 참석',
                  color: EncbaColors.attending,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MyAttendanceHighlight(
                  icon: Icons.emoji_events_rounded,
                  value: '${stats.bestStreak}회',
                  label: '최고 연속 참석',
                  color: EncbaColors.late,
                ),
              ),
            ],
          ),
          if (months.length >= 2) ...[
            const SizedBox(height: 18),
            const _MyAttendanceSection('월별 추이'),
            _MyAttendanceMonthChart(months: months),
          ],
          if (stats.byKind.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _MyAttendanceSection('일정 종류별'),
            for (final bucket in stats.byKind)
              _MyAttendanceRateBar(bucket: bucket),
          ],
          if (stats.byWeekday.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _MyAttendanceSection('요일별 경향'),
            for (final bucket in stats.byWeekday)
              _MyAttendanceRateBar(bucket: bucket, labelWidth: 36),
          ],
          if (stats.reasons.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _MyAttendanceSection('불참 사유'),
            for (final reason in stats.reasons)
              _MyAttendanceReasonRow(
                label: reason.key,
                count: reason.value,
                total: stats.absent,
              ),
          ],
          const SizedBox(height: 18),
          const _MyAttendanceSection('응답 기록'),
          for (final entry in stats.entries) _MyAttendanceEntryTile(entry: entry),
        ],
      ],
    );
  }
}

/// 표본이 적다는 사실을 숨기지 않고 알리는 안내 박스.
class _MyAttendanceNotice extends StatelessWidget {
  const _MyAttendanceNotice(this.template, {required this.count});

  final String template;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: EncbaColors.late.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: EncbaColors.late.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: EncbaColors.late,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              template.replaceFirst('0건', '$count건'),
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _MyAttendanceSection extends StatelessWidget {
  const _MyAttendanceSection(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: EncbaColors.deepBlue,
      ),
    ),
  );
}

class _MyAttendanceHighlight extends StatelessWidget {
  const _MyAttendanceHighlight({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: EncbaColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 참석률을 가로 진행 바로 보여주는 한 줄.
class _MyAttendanceRateBar extends StatelessWidget {
  const _MyAttendanceRateBar({required this.bucket, this.labelWidth = 62});

  final _MyAttendanceBucket bucket;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final rate = bucket.rate;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              bucket.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: rate ?? 0,
                minHeight: 9,
                backgroundColor: EncbaColors.line,
                valueColor: AlwaysStoppedAnimation(
                  rate == null || rate >= .7
                      ? EncbaColors.attending
                      : (rate >= .4 ? EncbaColors.late : EncbaColors.absent),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 74,
            child: Text(
              '${_ratePercent(rate)} (${bucket.attend}/${bucket.decided})',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: EncbaColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// 불참 사유 한 종류의 비중.
class _MyAttendanceReasonRow extends StatelessWidget {
  const _MyAttendanceReasonRow({
    required this.label,
    required this.count,
    required this.total,
  });

  final String label;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : count / total,
              minHeight: 9,
              backgroundColor: EncbaColors.line,
              valueColor: const AlwaysStoppedAnimation(EncbaColors.absent),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$count건',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: EncbaColors.muted),
          ),
        ),
      ],
    ),
  );
}

/// 월별 참석률 막대. 높이는 참석률, 숫자는 확정 응답 수를 나타낸다.
class _MyAttendanceMonthChart extends StatelessWidget {
  const _MyAttendanceMonthChart({required this.months});

  final List<_MyAttendanceBucket> months;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 108,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final bucket in months)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _ratePercent(bucket.rate),
                    style: const TextStyle(
                      fontSize: 10,
                      color: EncbaColors.muted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    height: 8 + 56 * (bucket.rate ?? 0),
                    decoration: BoxDecoration(
                      color: bucket.decided == 0
                          ? EncbaColors.line
                          : EncbaColors.snuBlue,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bucket.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                  Text(
                    '${bucket.total}건',
                    style: const TextStyle(
                      fontSize: 9,
                      color: EncbaColors.muted,
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

class _MyAttendanceEntryTile extends StatelessWidget {
  const _MyAttendanceEntryTile({required this.entry});

  final _MyAttendanceEntry entry;

  @override
  Widget build(BuildContext context) {
    final start = entry.event.start;
    final reason = entry.absenceReason?.trim() ?? '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        switch (entry.choice) {
          '참석' => Icons.check_circle_rounded,
          '불참' => Icons.cancel_rounded,
          _ => Icons.help_outline_rounded,
        },
        color: switch (entry.choice) {
          '참석' => EncbaColors.snuBlue,
          '불참' => EncbaColors.absent,
          _ => EncbaColors.muted,
        },
      ),
      title: Text(entry.event.title),
      subtitle: Text(
        '${start.month}.${start.day} (${weekday(start)}) · ${entry.event.kind.label} · '
        '${entry.choice}${reason.isEmpty ? '' : ' · $reason'}',
      ),
    );
  }
}
