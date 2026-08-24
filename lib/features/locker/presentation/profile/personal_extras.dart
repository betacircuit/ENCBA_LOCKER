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
}

/// 로그인한 사용자의 출결 응답을 모아 통계로 계산한다.
///
/// profileId는 Supabase profiles.id(=auth uid)와 같으므로 현재 사용자
/// id와 직접 비교한다. 응답이 없는 일정은 집계에서 뺀다.
({List<_MyAttendanceEntry> entries, int attend, int absent, int undecided})
_computeMyAttendance(List<LockerEvent> events, Map<String, List<AttendanceResponse>> attendance, String userId) {
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
  return (entries: entries, attend: attend, absent: absent, undecided: undecided);
}

Future<void> _showMyAttendance(BuildContext context, WidgetRef ref) async {
  final user = ref.read(authControllerProvider).user!;
  final state = ref.read(lockerControllerProvider);
  final result = _computeMyAttendance(
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
      final responded = result.attend + result.absent + result.undecided;
      final rate = result.attend + result.absent == 0
          ? null
          : (result.attend * 100 / (result.attend + result.absent)).round();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '내 출결 통계',
                style: Theme.of(sheetContext).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                responded == 0
                    ? '아직 응답한 일정이 없습니다.'
                    : '응답 $responded건 · 참석률 ${rate == null ? '-' : '$rate%'}',
                style: const TextStyle(color: EncbaColors.muted),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Stat(value: '${result.attend}', label: '참석'),
                      const _Rule(),
                      _Stat(value: '${result.absent}', label: '불참'),
                      const _Rule(),
                      _Stat(value: '${result.undecided}', label: '미정'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (result.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('일정 카드의 참석 버튼으로 응답하면 여기에 기록됩니다.')),
                )
              else
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: result.entries.length,
                      itemBuilder: (context, index) {
                        final entry = result.entries[index];
                        final start = entry.event.start;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
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
                            '${start.month}.${start.day} (${weekday(start)}) · '
                            '${entry.choice}${entry.absenceReason == null || entry.absenceReason!.isEmpty ? '' : ' · ${entry.absenceReason}'}',
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
