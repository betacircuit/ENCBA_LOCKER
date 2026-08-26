part of 'locker_shell.dart';

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) => _EventResolver(
    eventId: eventId,
    builder: (event) => _EventDetailView(initialEvent: event),
  );
}

class _EventDetailView extends ConsumerStatefulWidget {
  const _EventDetailView({required this.initialEvent});

  final LockerEvent initialEvent;

  @override
  ConsumerState<_EventDetailView> createState() => _EventDetailViewState();
}

class _EventDetailViewState extends ConsumerState<_EventDetailView> {
  @override
  void initState() {
    super.initState();
    if (!widget.initialEvent.id.startsWith('operation-')) {
      Future.microtask(() async {
        final controller = ref.read(lockerControllerProvider.notifier);
        await Future.wait([
          controller.loadEventAttendance(widget.initialEvent.id),
          controller.loadEventStrategy(widget.initialEvent.id),
        ]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventState = ref.watch(
      lockerControllerProvider.select(
        (state) => (
          events: state.eventsState.events,
          responses: state.eventsState.eventAttendance[widget.initialEvent.id],
          strategy: state.eventsState.eventStrategies[widget.initialEvent.id],
        ),
      ),
    );
    final events = eventState.events;
    final members = ref.watch(
      lockerControllerProvider.select((state) => state.membersState.members),
    );
    final event =
        events.where((item) => item.id == widget.initialEvent.id).firstOrNull ??
        widget.initialEvent;
    final responses = eventState.responses ?? const <AttendanceResponse>[];
    final isAdmin =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    final user = ref.watch(authControllerProvider).user;
    // 응답 독촉은 관리자가 스스로 '참석' 응답을 마친 뒤에만 쓸 수 있다.
    final myChoice = user == null
        ? null
        : responses
              .where((response) => response.profileId == user.id)
              .map((response) => response.choice)
              .firstOrNull;
    if (event.isLocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('외부 경기')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 40),
                const SizedBox(height: 14),
                Text(
                  event.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('출전 인원이 확정되면 선택된 부원에게만 상세 정보가 열립니다.'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final ok = await ref
                        .read(lockerControllerProvider.notifier)
                        .applyExternalEvent(event.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              ok ? '참여 신청을 보냈습니다.' : '신청을 저장하지 못했습니다.',
                            ),
                          ),
                        );
                    }
                  },
                  child: const Text('참여 신청'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('일정 상세'),
        actions: [
          if (isAdmin &&
              event.kind != EventKind.operations &&
              !event.isCancelled)
            IconButton(
              tooltip: '일정 수정',
              onPressed: () => context.push(
                '/schedule/${Uri.encodeComponent(event.id)}/edit',
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
        children: [
          Material(
            color: Colors.transparent,
            child: _ExpandedTicket(event: event),
          ),
          if (event.isCancelled) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE4E8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: EncbaColors.absent.withValues(alpha: .35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '일정이 취소되었습니다.',
                    style: TextStyle(
                      color: EncbaColors.absent,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  if (event.cancellationReason?.trim() case final String reason
                      when reason.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(reason),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          _EventDetailFacts(event: event),
          if (event.memo.trim().isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('안내', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 9),
            Text(event.memo, style: const TextStyle(height: 1.7)),
          ],
          if (event.starterNames.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('주전', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: event.starterNames
                  .map(
                    (name) => Chip(
                      avatar: const Icon(Icons.sports_basketball, size: 16),
                      label: Text(name),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (event.kind.isMatch) ...[
            const SizedBox(height: 22),
            _StrategyCard(
              event: event,
              strategy: eventState.strategy ?? EventStrategy(eventId: event.id),
            ),
          ],
          if (!event.isCancelled) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openMap(context, event),
                    icon: const Icon(Icons.near_me_outlined),
                    label: const Text('네이버 지도'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _addCalendar(context, event),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('캘린더에 추가'),
                  ),
                ),
              ],
            ),
          ],
          if (isAdmin && event.kind == EventKind.external) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push(
                '/schedule/${Uri.encodeComponent(event.id)}/roster',
              ),
              icon: const Icon(Icons.how_to_reg_outlined),
              label: const Text('출전 명단 확정'),
            ),
          ],
          if (event.responseEnabled && !event.isCancelled) ...[
            const SizedBox(height: 22),
            _AttendanceResponseCard(
              event: event,
              responses: responses,
              members: members,
            ),
            if (isAdmin) ...[
              const SizedBox(height: 10),
              _ResponseReminderButton(
                eventId: event.id,
                enabled: myChoice == '참석',
              ),
            ],
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EncbaColors.highlight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '수정 이력',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${event.createdBy} · ${event.updatedAt}\n일정 등록 및 최근 수정',
                  style: const TextStyle(
                    color: EncbaColors.muted,
                    fontSize: 12,
                    height: 1.5,
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

/// 관리자 전용 응답 독촉 버튼. 아직 응답하지 않은 활동 부원의 구독에
/// 푸시를 일괄 발송한다(send-push 엣지 함수의 response_reminder 호출).
class _ResponseReminderButton extends ConsumerStatefulWidget {
  const _ResponseReminderButton({required this.eventId, this.enabled = true});

  final String eventId;

  /// 관리자가 스스로 '참석' 응답을 마쳤을 때만 true. false면 버튼이
  /// 비활성화되고 이유를 툴팁으로 알려 준다.
  final bool enabled;

  @override
  ConsumerState<_ResponseReminderButton> createState() =>
      _ResponseReminderButtonState();
}

class _ResponseReminderButtonState
    extends ConsumerState<_ResponseReminderButton> {
  bool _sending = false;

  Future<void> _send() async {
    if (_sending || !widget.enabled) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('응답 독촉하기'),
        content: const Text(
          '아직 응답하지 않은 활동 부원에게 알림을 보낼까요? 이미 참석·불참을 고른 사람에게는 가지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('보내기'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    setState(() => _sending = true);
    final message = await ref
        .read(lockerControllerProvider.notifier)
        .remindEventNonresponders(widget.eventId);
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _sending || !widget.enabled ? null : _send,
        icon: _sending
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.notifications_active_outlined),
        label: Text(
          widget.enabled ? '응답 독촉하기' : '응답 독촉하기 — 내 응답(참석)을 먼저 눌러 주세요',
        ),
      ),
    );
    if (widget.enabled) return button;
    return Tooltip(
      message: '응답 독촉은 내 응답을 참석으로 누른 뒤에 사용할 수 있습니다.',
      child: button,
    );
  }
}

class _AttendanceResponseCard extends StatelessWidget {
  const _AttendanceResponseCard({
    required this.event,
    required this.responses,
    required this.members,
  });

  final LockerEvent event;
  final List<AttendanceResponse> responses;
  final List<MemberProfile> members;

  @override
  Widget build(BuildContext context) {
    final options = <String>[
      ...event.pollOptions,
      ...responses
          .map((response) => response.choice)
          .where((choice) => !event.pollOptions.contains(choice)),
    ];
    final uniqueOptions = options.toSet().toList(growable: false);
    final responseNames = responses
        .map((response) => response.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final unansweredNames =
        members
            .where((member) => member.isActiveMember)
            .map((member) => member.name.trim())
            .where((name) => name.isNotEmpty && !responseNames.contains(name))
            .toSet()
            .toList(growable: false)
          ..sort();

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: EncbaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 13),
            child: Row(
              children: [
                Text('참석 현황', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Text(
                  '${responses.length}명 응답',
                  style: const TextStyle(
                    color: EncbaColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (responses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '아직 응답이 없습니다.',
                style: TextStyle(color: EncbaColors.muted),
              ),
            )
          else
            ...uniqueOptions.indexed.map((entry) {
              final option = entry.$2;
              final optionResponses =
                  responses
                      .where((response) => response.choice == option)
                      .toList(growable: false)
                    ..sort((a, b) => a.name.compareTo(b.name));
              return _AttendanceOptionRow(
                index: entry.$1 + 1,
                option: option,
                responses: optionResponses,
                totalResponses: responses.length,
                showDivider: entry.$1 > 0,
              );
            }),
          if (unansweredNames.isNotEmpty) ...[
            const Divider(height: 1),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 18),
                childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 17),
                title: Text(
                  '미응답 ${unansweredNames.length}명',
                  style: const TextStyle(
                    color: EncbaColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      unansweredNames.join(', '),
                      style: const TextStyle(
                        color: EncbaColors.muted,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttendanceOptionRow extends StatelessWidget {
  const _AttendanceOptionRow({
    required this.index,
    required this.option,
    required this.responses,
    required this.totalResponses,
    required this.showDivider,
  });

  final int index;
  final String option;
  final List<AttendanceResponse> responses;
  final int totalResponses;
  final bool showDivider;

  Color get _color => switch (option) {
    '참석' => EncbaColors.attending,
    '불참' => EncbaColors.absent,
    '지각' => EncbaColors.late,
    '미정' => EncbaColors.undecided,
    _ => EncbaColors.deepBlue,
  };

  @override
  Widget build(BuildContext context) {
    final names = responses.map((response) => response.name).join(', ');
    final reasons = responses
        .where((response) => response.absenceReason?.trim().isNotEmpty ?? false)
        .toList(growable: false);
    final ratio = totalResponses == 0 ? 0.0 : responses.length / totalResponses;

    return Column(
      children: [
        if (showDivider) const Divider(height: 1, indent: 60),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 18, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _color.withValues(alpha: .12),
                child: Text(
                  '$index',
                  style: TextStyle(color: _color, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            option,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${responses.length}',
                          style: TextStyle(
                            color: _color,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        color: _color,
                        backgroundColor: EncbaColors.line,
                      ),
                    ),
                    if (names.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Text(
                        names,
                        style: const TextStyle(
                          color: EncbaColors.muted,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (reasons.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...reasons.map(
                        (response) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${response.name} · ${response.absenceReason!.trim()}',
                            style: const TextStyle(
                              color: EncbaColors.ink,
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StrategyCard extends ConsumerWidget {
  const _StrategyCard({required this.event, required this.strategy});

  final LockerEvent event;
  final EventStrategy strategy;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5FA),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: EncbaColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.draw_outlined, color: EncbaColors.snuBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '전술 · 전략',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => _edit(context, ref),
              child: Text(strategy.isEmpty ? '전술 짜기' : '수정'),
            ),
          ],
        ),
        if (strategy.isEmpty)
          const Text(
            '공격과 수비 약속을 팀원들과 공유해 보세요.',
            style: TextStyle(color: EncbaColors.muted),
          )
        else ...[
          if (strategy.offense.isNotEmpty)
            _StrategyLine('공격', strategy.offense),
          if (strategy.defense.isNotEmpty)
            _StrategyLine('수비', strategy.defense),
          if (strategy.notes.isNotEmpty) _StrategyLine('메모', strategy.notes),
          if (strategy.updatedBy.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              '${strategy.updatedBy} 수정',
              style: const TextStyle(color: EncbaColors.muted, fontSize: 11),
            ),
          ],
        ],
      ],
    ),
  );

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final offense = TextEditingController(text: strategy.offense);
    final defense = TextEditingController(text: strategy.defense);
    final notes = TextEditingController(text: strategy.notes);
    final result = await showModalBottomSheet<EventStrategy>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '전술 · 전략',
                  style: TextStyle(
                    fontFamily: 'Jua',
                    fontSize: 25,
                    color: EncbaColors.navy,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: offense,
                  minLines: 2,
                  maxLines: 5,
                  scrollPadding: const EdgeInsets.only(bottom: 220),
                  decoration: const InputDecoration(
                    labelText: '공격',
                    hintText: '세트 오펜스, 스크린 약속, 첫 옵션',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: defense,
                  minLines: 2,
                  maxLines: 5,
                  scrollPadding: const EdgeInsets.only(bottom: 180),
                  decoration: const InputDecoration(
                    labelText: '수비',
                    hintText: '매치업, 헬프 위치, 리바운드 약속',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 5,
                  scrollPadding: const EdgeInsets.only(bottom: 140),
                  decoration: const InputDecoration(
                    labelText: '추가 메모',
                    hintText: '타임아웃 때 확인할 한 문장',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    sheetContext,
                    EventStrategy(
                      eventId: event.id,
                      offense: offense.text,
                      defense: defense.text,
                      notes: notes.text,
                    ),
                  ),
                  child: const Text('전술 저장'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    offense.dispose();
    defense.dispose();
    notes.dispose();
    if (result == null) return;
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .saveEventStrategy(result);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(saved ? '전술을 저장했습니다.' : '전술 저장에 실패했습니다.')),
        );
    }
  }
}

class _StrategyLine extends StatelessWidget {
  const _StrategyLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: const TextStyle(
              color: EncbaColors.snuBlue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(height: 1.5))),
      ],
    ),
  );
}
