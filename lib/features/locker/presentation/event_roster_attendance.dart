part of 'locker_shell.dart';

class EventRosterScreen extends StatelessWidget {
  const EventRosterScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) => _EventResolver(
    eventId: eventId,
    builder: (event) => _EventRosterView(event: event),
  );
}

class _EventRosterView extends ConsumerStatefulWidget {
  const _EventRosterView({required this.event});

  final LockerEvent event;

  @override
  ConsumerState<_EventRosterView> createState() => _EventRosterViewState();
}

class _EventRosterViewState extends ConsumerState<_EventRosterView> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(lockerControllerProvider.notifier)
          .loadEventRoster(widget.event.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roster =
        ref.watch(
          lockerControllerProvider.select(
            (state) => state.eventsState.eventRosters[widget.event.id],
          ),
        ) ??
        const <EventRosterMember>[];
    return Scaffold(
      appBar: AppBar(title: const Text('출전 명단 확정')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.event.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text('참여 신청자를 확정하면 해당 부원에게만 경기 상세가 열립니다.'),
          const SizedBox(height: 18),
          if (roster.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('아직 참여 신청자가 없습니다.'),
              ),
            )
          else
            ...roster.map(
              (member) => Card(
                child: ListTile(
                  title: Text(member.name),
                  subtitle: Text(switch (member.status) {
                    'confirmed' => '출전 확정',
                    'declined' => '미선발',
                    _ => '참여 신청',
                  }),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'confirmed', label: Text('확정')),
                      ButtonSegment(value: 'declined', label: Text('제외')),
                    ],
                    selected: {
                      member.status == 'applied' ? 'declined' : member.status,
                    },
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => ref
                        .read(lockerControllerProvider.notifier)
                        .setEventRosterStatus(
                          eventId: widget.event.id,
                          member: member,
                          status: selection.first,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExpandedTicket extends StatelessWidget {
  const _ExpandedTicket({required this.event});
  final LockerEvent event;

  @override
  Widget build(BuildContext context) {
    final accent = _kindColor(event.kind);
    const detailBackground = EncbaColors.navy;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: detailBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: detailBackground),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EventKindLabel(kind: event.kind, inverted: true),
              const Spacer(),
              if (event.uniformColors.isNotEmpty)
                Text(
                  '${event.uniformColors.join(' · ')} 유니폼',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            event.title,
            style: TextStyle(
              fontFamily: encbaFontFor(event.title, display: true),
              color: Colors.white,
              fontSize: 32,
              height: 1.1,
            ),
          ),
          if (event.opponents.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'vs ${event.opponents.join(' · ')}',
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
          const SizedBox(height: 18),
          _MetaLine(
            icon: Icons.calendar_today_outlined,
            text:
                '${event.start.month}월 ${event.start.day}일 (${weekday(event.start)}) · ${time(event.start)}–${time(event.end)}',
            color: EncbaColors.navy,
            emphasized: true,
            markerColor: EncbaColors.timeMarker,
          ),
          const SizedBox(height: 9),
          _MetaLine(
            icon: Icons.location_on_outlined,
            text: event.fullPlace,
            color: EncbaColors.navy,
            emphasized: true,
            markerColor: EncbaColors.placeMarker,
          ),
          const SizedBox(height: 18),
          Container(height: 2, width: 70, color: accent),
          const SizedBox(height: 12),
          Text(
            '${event.targetTeam} · ${event.attending}명 참석 예정${event.capacity == null ? '' : ' / ${event.capacity}명'}',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (event.obParticipantCount > 0) ...[
            const SizedBox(height: 5),
            Text(
              'OB ${event.obParticipantCount}명 참여',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _EventDetailFacts extends StatelessWidget {
  const _EventDetailFacts({required this.event});

  final LockerEvent event;

  @override
  Widget build(BuildContext context) {
    final opponent = event.opponents.isEmpty
        ? '미정'
        : event.opponents.join(' · ');
    final uniform = event.uniformColors.isEmpty
        ? '미정'
        : event.uniformColors.join(' · ');
    final dateTime =
        '${event.start.year}년 ${event.start.month}월 ${event.start.day}일 '
        '(${weekday(event.start)}) ${time(event.start)}–${time(event.end)}';

    return Semantics(
      container: true,
      label: '일정 정보',
      child: Container(
        key: const ValueKey('event-detail-facts'),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: EncbaColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('일정 정보', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            _EventDetailFactRow(
              icon: Icons.groups_2_outlined,
              label: '상대',
              value: opponent,
            ),
            const SizedBox(height: 12),
            _EventDetailFactRow(
              icon: Icons.checkroom_outlined,
              label: '유니폼',
              value: uniform,
            ),
            const SizedBox(height: 12),
            _EventDetailFactRow(
              icon: Icons.schedule_outlined,
              label: '일시',
              value: dateTime,
            ),
            const SizedBox(height: 12),
            _EventDetailFactRow(
              icon: Icons.location_on_outlined,
              label: '장소',
              value: event.fullPlace,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventDetailFactRow extends StatelessWidget {
  const _EventDetailFactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: EncbaColors.snuBlue),
      const SizedBox(width: 10),
      SizedBox(
        width: 50,
        child: Text(
          label,
          style: const TextStyle(
            color: EncbaColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
        ),
      ),
    ],
  );
}

class AttendanceSelector extends ConsumerWidget {
  const AttendanceSelector({
    super.key,
    required this.event,
    this.compact = false,
    this.flush = false,
  });
  final LockerEvent event;
  final bool compact;
  final bool flush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      lockerControllerProvider.select(
        (state) => state.eventsState.attendance[event.id],
      ),
    );
    final isAdmin =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    final isClosed = DateTime.now().isAfter(event.responseDeadline) && !isAdmin;
    final choices = event.pollOptions
        .map((label) => (label, _choiceIcon(label), _choiceColor(label)))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = choices.length <= 4 ? choices.length : 2;
        final spacing = flush ? 0.0 : 7.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: choices.map((choice) {
            final active = selected == choice.$1;
            return SizedBox(
              width: width,
              child: Semantics(
                selected: active,
                button: true,
                child: InkWell(
                  borderRadius: flush
                      ? BorderRadius.zero
                      : BorderRadius.circular(13),
                  onTap: isClosed
                      ? null
                      : () async {
                          final revision =
                              (_attendanceUiRevisions[event.id] ?? 0) + 1;
                          _attendanceUiRevisions[event.id] = revision;
                          String? reason;
                          if (choice.$1 == '불참') {
                            reason = await _askAbsenceReason(context);
                            if (reason == null) return;
                          }
                          final saved = await ref
                              .read(lockerControllerProvider.notifier)
                              .vote(event.id, choice.$1, absenceReason: reason);
                          if (_attendanceUiRevisions[event.id] != revision) {
                            return;
                          }
                          if (!context.mounted) return;
                          final showedConfirmation =
                              saved && choice.$1 == '참석' && !active;
                          if (saved) {
                            if (showedConfirmation) {
                              unawaited(HapticFeedback.mediumImpact());
                              _showAttendanceCelebration(context);
                            }
                            await ref
                                .read(lockerControllerProvider.notifier)
                                .loadEventAttendance(event.id);
                          }
                          if (context.mounted && !showedConfirmation) {
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    saved
                                        ? '${choice.$1}으로 저장했습니다.'
                                        : '응답을 저장하지 못했습니다.',
                                  ),
                                ),
                              );
                          }
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: compact ? 42 : 68,
                    decoration: BoxDecoration(
                      color: active
                          ? choice.$3
                          : choice.$3.withValues(alpha: .09),
                      borderRadius: flush
                          ? BorderRadius.zero
                          : BorderRadius.circular(13),
                      border: Border.all(
                        color: choice.$3.withValues(alpha: active ? 1 : .25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!compact) ...[
                          Icon(
                            choice.$2,
                            size: 20,
                            color: active ? Colors.white : choice.$3,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          choice.$1,
                          style: TextStyle(
                            color: active ? Colors.white : choice.$3,
                            fontSize: compact ? 12 : 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  IconData _choiceIcon(String value) => switch (value) {
    '참석' => Icons.check_rounded,
    '불참' => Icons.close_rounded,
    '지각' => Icons.schedule_rounded,
    _ => Icons.more_horiz_rounded,
  };

  Color _choiceColor(String value) => switch (value) {
    '참석' => EncbaColors.attending,
    '불참' => EncbaColors.absent,
    '지각' => EncbaColors.late,
    _ => EncbaColors.undecided,
  };

  Future<String?> _askAbsenceReason(BuildContext context) => showDialog<String>(
    context: context,
    builder: (context) => const _AbsenceReasonDialog(),
  );
}

/// 밴드에서 실제로 가장 많이 쌓인 불참 사유 5종.
///
/// 선택지와 출결 통계의 분류가 어긋나지 않도록 목록은 여기서만 정의한다.
const absenceReasonPresets = <String>['가족 일정', '학업', '개인 선약', '여행', '부상·건강'];

/// 불참을 확정하려면 그대로 입력해야 하는 문구.
const absenceConfirmPhrase = '불참하겠습니다';

/// 직접 입력 선택지 라벨. 이 값 자체는 사유로 저장되지 않는다.
const _absenceCustomLabel = '직접 입력';

/// 선택지를 그대로 저장하면 일정 상세에서 "이름 · 학업"처럼 딱딱하게 읽힌다.
/// 밴드 댓글처럼 보이도록 문장으로 바꿔 저장한다.
const _absenceReasonSentences = <String, String>{
  '가족 일정': '가족 일정이 있어서 불참합니다.',
  '학업': '학업 일정이 있어서 불참합니다.',
  '개인 선약': '개인 선약이 있어서 불참합니다.',
  '여행': '여행 일정이 있어서 불참합니다.',
  '부상·건강': '부상·건강 문제로 불참합니다.',
};

/// 저장된 사유 문장을 다시 선택지 라벨로 되돌린다. 통계 분류가 문장 형태
/// 변경에 흔들리지 않게 하기 위한 역매핑이며, 예전에 라벨만 저장된 기록도
/// 그대로 알아본다.
String? absenceReasonPresetOf(String reason) {
  final trimmed = reason.trim();
  for (final label in absenceReasonPresets) {
    if (trimmed == label || trimmed == _absenceReasonSentences[label]) {
      return label;
    }
  }
  return null;
}

const _absenceReasonHints = <String, String>{
  '가족 일정': '본가 방문, 가족 여행, 가족 행사',
  '학업': '시험, 기말고사, 과제·프로젝트 마감, 세미나',
  '개인 선약': '미리 잡아 둔 약속',
  '여행': '개인 여행, 해외여행',
  '부상·건강': '부상, 감기, 고열 등',
  _absenceCustomLabel: '위 다섯 가지에 해당하지 않을 때만 사용해 주세요.',
};

/// 불참 사유를 고르고 확인 문구까지 입력해야 통과되는 다이얼로그.
class _AbsenceReasonDialog extends StatefulWidget {
  const _AbsenceReasonDialog();

  @override
  State<_AbsenceReasonDialog> createState() => _AbsenceReasonDialogState();
}

class _AbsenceReasonDialogState extends State<_AbsenceReasonDialog> {
  String? _selected;
  final _customController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// 저장될 사유 문자열. 선택지는 문장으로, 직접 입력은 적은 내용을 쓴다.
  String? get _reason {
    final selected = _selected;
    if (selected == null) return null;
    if (selected != _absenceCustomLabel) {
      return _absenceReasonSentences[selected] ?? selected;
    }
    final typed = _customController.text.trim();
    return typed.isEmpty ? null : typed;
  }

  bool get _confirmed => _confirmController.text.trim() == absenceConfirmPhrase;

  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    final canSubmit = reason != null && _confirmed;
    return AlertDialog(
      title: const Text('불참 사유'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '불참 사유를 골라 주세요.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final label in [
                ...absenceReasonPresets,
                _absenceCustomLabel,
              ])
                _reasonTile(label),
              if (_selected == _absenceCustomLabel) ...[
                const SizedBox(height: 4),
                TextField(
                  controller: _customController,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '불참 사유를 직접 적어 주세요.',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                "확정하려면 아래에 '$absenceConfirmPhrase'를 그대로 입력해 주세요.",
                style: TextStyle(fontSize: 12, color: EncbaColors.ink),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _confirmController,
                maxLength: 20,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: absenceConfirmPhrase,
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: canSubmit ? () => Navigator.pop(context, reason) : null,
          child: const Text('불참 확정'),
        ),
      ],
    );
  }

  Widget _reasonTile(String label) {
    final active = _selected == label;
    final hint = _absenceReasonHints[label];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => setState(() => _selected = label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: active ? EncbaColors.absent.withValues(alpha: .08) : null,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: active ? EncbaColors.absent : EncbaColors.line,
            ),
          ),
          child: Row(
            children: [
              Icon(
                active
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: active ? EncbaColors.absent : EncbaColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: active ? EncbaColors.absent : EncbaColors.ink,
                      ),
                    ),
                    if (hint != null)
                      Text(
                        hint,
                        style: const TextStyle(
                          fontSize: 11,
                          color: EncbaColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showAttendanceCelebration(BuildContext context) {
  if (MediaQuery.disableAnimationsOf(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AttendanceCelebration(onComplete: entry.remove),
  );
  overlay.insert(entry);
}

class _AttendanceCelebration extends StatefulWidget {
  const _AttendanceCelebration({required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_AttendanceCelebration> createState() => _AttendanceCelebrationState();
}

class _AttendanceCelebrationState extends State<_AttendanceCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward().whenComplete(widget.onComplete);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      key: const ValueKey('attendance-celebration'),
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value;
            final scale = Curves.elasticOut.transform(
              math.min(progress / .62, 1),
            );
            final opacity = progress < .7 ? 1.0 : (1 - progress) / .3;
            return CustomPaint(
              painter: _AttendanceBurstPainter(progress),
              child: Center(
                child: Opacity(
                  opacity: opacity.clamp(0, 1),
                  child: Transform.scale(
                    scale: scale,
                    child: Semantics(
                      liveRegion: true,
                      label: '참석 확정',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF29A36A), Color(0xFF096540)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: EncbaColors.attending.withValues(
                                    alpha: .34,
                                  ),
                                  blurRadius: 30,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Material(
                            color: const Color(0xFF092E22),
                            borderRadius: BorderRadius.circular(999),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Text(
                                '참석 확정!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Jua',
                                  fontSize: 17,
                                  letterSpacing: .2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AttendanceBurstPainter extends CustomPainter {
  const _AttendanceBurstPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 38);
    final travel = Curves.easeOutCubic.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0);
    final ringPaint = Paint()
      ..color = EncbaColors.attending.withValues(alpha: fade * .32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * fade;
    canvas.drawCircle(center, 45 + 105 * travel, ringPaint);

    const colors = [Color(0xFF167A50), Color(0xFFFFB02E), Color(0xFFE96B2C)];
    for (var index = 0; index < 18; index++) {
      final angle = -math.pi / 2 + index * (2 * math.pi / 18);
      final distance = 48 + (92 + (index % 3) * 15) * travel;
      final particleCenter =
          center +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance);
      final paint = Paint()
        ..color = colors[index % colors.length].withValues(alpha: fade);
      final radius = (index.isEven ? 5.0 : 3.5) * fade;
      canvas.drawCircle(particleCenter, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AttendanceBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .82)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(1, size.height * .18)
      ..lineTo(size.width - 3, 0)
      ..lineTo(size.width, size.height * .82)
      ..lineTo(4, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter oldDelegate) =>
      oldDelegate.color != color;
}

Color _kindColor(EventKind kind) => switch (kind) {
  EventKind.training => EncbaColors.snuBlue,
  EventKind.morning => const Color(0xFFD4A017),
  EventKind.freeOpen => const Color(0xFF2A7C67),
  EventKind.internal => EncbaColors.deepBlue,
  EventKind.pickup => EncbaColors.deepBlue,
  EventKind.ibDivision1 => const Color(0xFF4B2A75),
  EventKind.ibDivision2 || EventKind.ibFreshman => const Color(0xFF6D43A6),
  EventKind.scrimmage ||
  EventKind.threeWay ||
  EventKind.external => EncbaColors.absent,
  EventKind.operations => EncbaColors.late,
  EventKind.homecoming => const Color(0xFFC6283D),
};

({Color? color, Gradient? gradient, bool dark, bool split})
_uniformCardDecoration(LockerEvent event) {
  if (event.isCancelled) {
    return (
      color: const Color(0xFFFFECEF),
      gradient: null,
      dark: false,
      split: false,
    );
  }
  if (event.kind == EventKind.homecoming ||
      event.kind == EventKind.operations) {
    return (
      color: const Color(0xFF9B1C31),
      gradient: null,
      dark: true,
      split: false,
    );
  }
  return (color: Colors.white, gradient: null, dark: false, split: false);
}

class _UniformCardForeground extends StatelessWidget {
  const _UniformCardForeground({required this.decoration, required this.child});

  final ({Color? color, Gradient? gradient, bool dark, bool split}) decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final foreground = decoration.dark ? Colors.white : EncbaColors.ink;
    Widget content = IconTheme.merge(
      data: IconThemeData(color: foreground),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: child,
      ),
    );
    if (!decoration.split) return content;
    content = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Colors.white, Colors.white, EncbaColors.ink, EncbaColors.ink],
        stops: [0, .46, .46, 1],
      ).createShader(bounds),
      child: content,
    );
    return content;
  }
}

String time(DateTime value) => DateFormat('HH:mm').format(value);
String weekday(DateTime value) =>
    const ['월', '화', '수', '목', '금', '토', '일'][value.weekday - 1];

Future<void> _openMap(BuildContext context, LockerEvent event) async {
  const places = {
    '71동 종합체육관':
        'https://map.naver.com/p/entry/place/18733898?c=15.00,0,0,0,dh',
    '71-1동 신체육관':
        'https://map.naver.com/p/entry/place/1985573410?c=15.00,0,0,0,dh',
    '900동 기숙사체육관':
        'https://map.naver.com/p/search/%EC%84%9C%EC%9A%B8%EB%8C%80%EA%B8%B0%EC%88%99%EC%82%AC900%EB%8F%99/place/1289118439?c=15.00,0,0,0,dh',
  };
  final reference = event.mapReference?.trim();
  final pastedUri = reference == null ? null : Uri.tryParse(reference);
  final isWebLink =
      pastedUri != null &&
      (pastedUri.scheme == 'https' || pastedUri.scheme == 'http');
  final target = reference != null && reference.isNotEmpty
      ? (isWebLink
            ? reference
            : 'https://map.naver.com/p/search/${Uri.encodeComponent(reference)}')
      : places[event.place] ??
            'https://map.naver.com/p/search/${Uri.encodeComponent(event.fullPlace)}';
  final uri = Uri.parse(target);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('네이버 지도를 열 수 없습니다.')));
  }
}

Future<void> _addCalendar(BuildContext context, LockerEvent event) async {
  final success = await addEventToCalendar(event);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(success ? '캘린더 추가 화면을 열었습니다.' : '이 기기에서는 캘린더를 열 수 없습니다.'),
      ),
    );
}
