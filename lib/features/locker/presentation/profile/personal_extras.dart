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

const _pwaDismissKey = 'encba.pwa-install-dismissed.v1';

/// iOS Safari 등 "브라우저에서 그냥 열린" 상태에서만 보이는 홈 화면 추가
/// 안내. 설치(standalone) 상태이거나 다시 보지 않기를 고르면 사라진다.
class _PwaInstallCard extends ConsumerStatefulWidget {
  const _PwaInstallCard();

  @override
  ConsumerState<_PwaInstallCard> createState() => _PwaInstallCardState();
}

class _PwaInstallCardState extends ConsumerState<_PwaInstallCard> {
  bool? _dismissed;

  /// 저장소를 쓸 수 없는 환경(테스트 등)에서도 화면이 깨지지 않게 한다.
  /// 읽기 실패는 "아직 숨기지 않음"으로, 쓰기 실패는 무시한다.
  Future<bool> _readDismissed() async {
    try {
      return await LocalStore().getString(_pwaDismissKey) == 'true';
    } on Object {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final dismissed = await _readDismissed();
      if (mounted) setState(() => _dismissed = dismissed);
    });
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    try {
      await LocalStore().setString(_pwaDismissKey, 'true');
    } on Object {
      // 저장에 실패해도 이번 세션에는 숨긴다.
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = const AppEnvironmentImpl();
    // 네이티브 앱·설치된 PWA·안내 숨김에는 보이지 않는다.
    if (_dismissed != false || !env.isAppleMobileWeb || env.isStandalone) {
      return const SizedBox.shrink();
    }
    return Card(
      color: EncbaColors.highlight,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.add_to_home_screen_rounded,
                    color: EncbaColors.snuBlue),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    '홈 화면에 추가하고 앱처럼 쓰기',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: '다시 보지 않기',
                  onPressed: _dismiss,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 6),
              child: Text(
                'Safari 공유 버튼 → "홈 화면에 추가"를 누르면\nLOCKER 아이콘으로 전체 화면 앱처럼 실행됩니다.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _showSteps(context),
                child: const Text('자세히'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSteps(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'iPhone·iPad에서 설치하기',
                style: TextStyle(fontFamily: 'Jua', fontSize: 22),
              ),
              const SizedBox(height: 14),
              _step('1', 'Safari 상단의 공유 버튼을 누릅니다.',
                  Icons.ios_share_rounded),
              _step('2', '목록을 아래로 스크롤해 "홈 화면에 추가"를 고릅니다.',
                  Icons.add_rounded),
              _step('3', '이름이 LOCKER로 저장되어 있는지 확인하고 추가합니다.',
                  Icons.check_rounded),
              _step('4', '홈 화면의 LOCKER 아이콘으로 전체 화면 앱처럼 실행합니다.',
                  Icons.phone_iphone_rounded),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('알겠어요'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(String number, String text, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: EncbaColors.snuBlue,
          child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
        const SizedBox(width: 11),
        Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
        Icon(icon, size: 19, color: EncbaColors.muted),
      ],
    ),
  );
}