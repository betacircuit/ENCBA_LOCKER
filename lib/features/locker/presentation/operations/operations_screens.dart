part of '../locker_shell.dart';

class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});

  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  List<OperationAssignment>? _allAssignments;
  bool _loadingAll = false;

  /// 관리자 섹션을 목록 대신 학기 타임라인으로 보여 준다.
  bool _timelineView = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(lockerControllerProvider.notifier).refreshOperationSwaps(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final operationsState = ref.watch(
      lockerControllerProvider.select(
        (state) => (
          operations: state.operationsState.operations,
          swapRequests: state.operationsState.operationSwapRequests,
          exchangeBoard: state.operationsState.operationExchangeBoard,
        ),
      ),
    );
    final operations = operationsState.operations;
    final pendingRequests = operationsState.swapRequests
        .where((request) => request.status == 'pending')
        .toList(growable: false);
    final exchangeTargets = operationsState.exchangeBoard
        .where((assignment) => !assignment.isMine)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('IB 운영 일정')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (pendingRequests.isNotEmpty) ...[
            const Text(
              '교환 요청',
              style: TextStyle(
                fontFamily: 'Jua',
                fontSize: 27,
                color: EncbaColors.navy,
              ),
            ),
            const SizedBox(height: 12),
            ...pendingRequests.map(_swapRequestCard),
            const SizedBox(height: 24),
          ],
          const Text(
            '내가 맡은 일',
            style: TextStyle(
              fontFamily: 'Jua',
              fontSize: 27,
              color: EncbaColors.navy,
            ),
          ),
          const SizedBox(height: 14),
          if (operations.isEmpty)
            const _EmptyState(
              icon: Icons.assignment_outlined,
              title: '배정된 운영 일정이 없습니다',
            )
          else
            ...operations.map(
              (item) => _TaskTile(
                date: '${item.start.month}/${item.start.day}',
                title: item.title,
                place: '${time(item.start)} · ${item.location}',
                onTap: () => _showTask(context, item.memo),
              ),
            ),
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '교환 가능한 운영',
                  style: TextStyle(
                    fontFamily: 'Jua',
                    fontSize: 27,
                    color: EncbaColors.navy,
                  ),
                ),
              ),
              IconButton(
                tooltip: '새로고침',
                onPressed: () => ref
                    .read(lockerControllerProvider.notifier)
                    .refreshOperationSwaps(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '상대 일정을 고른 뒤 내 일정과 맞교환을 신청합니다.',
            style: TextStyle(color: EncbaColors.muted),
          ),
          const SizedBox(height: 12),
          if (exchangeTargets.isEmpty)
            const _EmptyState(
              icon: Icons.swap_horiz_rounded,
              title: '교환 가능한 운영 일정이 없습니다',
            )
          else
            ...exchangeTargets
                .take(40)
                .map(
                  (item) => _TaskTile(
                    date: '${item.start.month}/${item.start.day}',
                    title: '${item.title} · ${item.assigneeName}',
                    place: '${time(item.start)} · ${item.location}',
                    onTap: () => _requestSwap(item),
                  ),
                ),
            ..._allAssignmentsSection(
              canEdit:
                  ref.watch(authControllerProvider).user?.canAdminister ?? false,
            ),
        ],
      ),
    );
  }

  /// 학기 전체 운영 배정. 모두가 볼 수 있고, 수정은 관리자만 허용된다.
  /// 부원 화면과 같은 목록 위젯을 재사용해 두 화면이 어긋나지 않게 한다.
  List<Widget> _allAssignmentsSection({required bool canEdit}) {
    final assignments = _allAssignments;
    return [
      const SizedBox(height: 28),
      Row(
        children: [
          Expanded(
            child: Text(
              canEdit ? '전체 운영 일정 (관리자)' : '전체 운영 일정',
              style: const TextStyle(
                fontFamily: 'Jua',
                fontSize: 27,
                color: EncbaColors.navy,
              ),
            ),
          ),
          IconButton(
            tooltip: _timelineView ? '목록 보기' : '타임라인 보기',
            onPressed: () => setState(() => _timelineView = !_timelineView),
            icon: Icon(_timelineView ? Icons.list_rounded : Icons.timeline),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _loadingAll ? null : _loadAllAssignments,
            icon: _loadingAll
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        _timelineView
            ? canEdit
                ? '학기 전체 운영 흐름을 한눈에 봅니다. 항목을 누르면 수정합니다.'
                : '학기 전체 운영 흐름을 한눈에 봅니다.'
            : canEdit
            ? '모든 부원의 IB 운영 배정을 확인하고 시간·장소·메모를 바로 수정합니다.'
            : '모든 부원의 IB 운영 배정을 확인할 수 있습니다. 수정은 관리자만 할 수 있어요.',
        style: const TextStyle(color: EncbaColors.muted),
      ),
      const SizedBox(height: 12),
      if (assignments == null && !_loadingAll)
        OutlinedButton.icon(
          onPressed: _loadAllAssignments,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('전체 배정 불러오기'),
        )
      else if (_loadingAll)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (assignments!.isEmpty)
        const _EmptyState(
          icon: Icons.assignment_late_outlined,
          title: '등록된 운영 배정이 없습니다',
        )
      else if (_timelineView)
        ..._buildSemesterTimeline(assignments, canEdit: canEdit)
      else
        ...assignments.map(
          (item) => _TaskTile(
            date: '${item.start.month}/${item.start.day}',
            title: '${item.title} · ${item.assigneeName}',
            place: '${time(item.start)} · ${item.location}',
            onTap: canEdit ? () => _editAssignment(item) : null,
          ),
        ),
    ];
  }

  /// 학기 타임라인: 월별로 묶어 왼쪽 점선 축에 날짜를 찍어 보여 준다.
  List<Widget> _buildSemesterTimeline(
    List<OperationAssignment> items, {
    required bool canEdit,
  }) {
    final byMonth = <String, List<OperationAssignment>>{};
    for (final item in items) {
      byMonth.putIfAbsent('${item.start.year}.${item.start.month}', () => []).add(item);
    }
    final widgets = <Widget>[];
    for (final entry in byMonth.entries) {
      widgets.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: EncbaColors.highlight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${entry.key}월',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: EncbaColors.deepBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entry.value.length}건',
                style: const TextStyle(color: EncbaColors.muted, fontSize: 12),
              ),
            ],
          ),
        ));
      for (final item in entry.value) {
        widgets.add(
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: canEdit ? () => _editAssignment(item) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 16),
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: EncbaColors.snuBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Container(
                            width: 2,
                            color: EncbaColors.line.withValues(alpha: .7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 2,
                          ),
                          title: Text(
                            '${item.start.day}일 (${_weekdayLabel(item.start.weekday)}) ${time(item.start)} · ${item.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${item.assigneeName} · ${item.location.isEmpty ? '장소 미정' : item.location}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: EncbaColors.muted,
                          ),
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
    return widgets;
  }

  String _weekdayLabel(int weekday) => switch (weekday) {
    DateTime.monday => '월',
    DateTime.tuesday => '화',
    DateTime.wednesday => '수',
    DateTime.thursday => '목',
    DateTime.friday => '금',
    DateTime.saturday => '토',
    _ => '일',
  };

  Future<void> _loadAllAssignments() async {
    setState(() => _loadingAll = true);
    final assignments = await ref
        .read(lockerControllerProvider.notifier)
        .loadAllOperations();
    if (!mounted) return;
    setState(() {
      _allAssignments = assignments;
      _loadingAll = false;
    });
  }

  Future<void> _editAssignment(OperationAssignment assignment) async {
    var start = assignment.start;
    var end = assignment.end;
    final title = TextEditingController(text: assignment.title);
    final location = TextEditingController(text: assignment.location);
    final memo = TextEditingController(text: assignment.memo);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${assignment.assigneeName} 배정 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '제목'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(labelText: '장소'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: start,
                      firstDate: DateTime(start.year - 1),
                      lastDate: DateTime(start.year + 2),
                    );
                    if (date == null) return;
                    setDialogState(() {
                      start = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        start.hour,
                        start.minute,
                      );
                      end = start.add(end.difference(assignment.start));
                    });
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('${start.month}/${start.day} (${start.weekday})'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(start),
                          );
                          if (picked == null) return;
                          setDialogState(() {
                            start = DateTime(
                              start.year,
                              start.month,
                              start.day,
                              picked.hour,
                              picked.minute,
                            );
                          });
                        },
                        child: Text('시작 ${time(start)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(end),
                          );
                          if (picked == null) return;
                          setDialogState(() {
                            end = DateTime(
                              end.year,
                              end.month,
                              end.day,
                              picked.hour,
                              picked.minute,
                            );
                          });
                        },
                        child: Text('종료 ${time(end)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: memo,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '메모'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: title.text.trim().isEmpty || !end.isAfter(start)
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || saved != true) {
      title.dispose();
      location.dispose();
      memo.dispose();
      return;
    }
    final ok = await ref
        .read(lockerControllerProvider.notifier)
        .updateOperationAssignment(
          assignment: assignment,
          start: start,
          end: end,
          title: title.text.trim(),
          location: location.text.trim(),
          memo: memo.text.trim(),
        );
    title.dispose();
    location.dispose();
    memo.dispose();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(ok ? '수정했습니다.' : '수정하지 못했습니다.')));
    await _loadAllAssignments();
  }

  Widget _swapRequestCard(OperationSwapRequest request) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: request.incoming ? const Color(0xFFFFF5DF) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: EncbaColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          request.incoming
              ? '${request.counterpartName}님의 교환 신청'
              : '${request.counterpartName}님에게 보낸 신청',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 7),
        Text(
          '${request.requesterTitle} ↔ ${request.targetTitle}',
          style: const TextStyle(color: EncbaColors.navy),
        ),
        if (request.message.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(request.message),
        ],
        if (request.incoming) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _respondSwap(request, false),
                  child: const Text('거절'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _respondSwap(request, true),
                  child: const Text('교환 수락'),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Future<void> _requestSwap(OperationAssignment target) async {
    final own = ref.read(lockerControllerProvider).operations;
    if (own.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('교환할 내 운영 일정이 없습니다.')));
      return;
    }
    var selectedId = own.first.id;
    final message = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('IB 운영 교환 신청'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${target.assigneeName} · ${target.start.month}/${target.start.day} ${time(target.start)}',
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '교환할 내 일정'),
                  items: own
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            '${item.start.month}/${item.start.day} ${time(item.start)} · ${item.title}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedId = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  maxLength: 300,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '메시지',
                    hintText: '교환을 부탁하는 이유를 적어 주세요. (선택)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('신청 보내기'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      message.dispose();
      return;
    }
    final typedMessage = message.text.trim();
    message.dispose();
    if (approved != true) return;
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .requestOperationSwap(
          ownAssignmentId: selectedId,
          targetAssignmentId: target.id,
          message: typedMessage,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(saved ? 'IB 운영 교환 신청을 보냈습니다.' : '교환 신청을 보내지 못했습니다.'),
        ),
      );
  }

  Future<void> _respondSwap(OperationSwapRequest request, bool accept) async {
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .respondOperationSwap(requestId: request.id, accept: accept);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? accept
                      ? 'IB 운영 일정이 교환되었습니다.'
                      : '교환 요청을 거절했습니다.'
                : '교환 응답을 저장하지 못했습니다.',
          ),
      ),
    );
  }

}

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(lockerControllerProvider.notifier).loadAuditEntries(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(
      lockerControllerProvider.select(
        (state) => state.operationsState.auditEntries,
      ),
    );
    final groups = _groupAuditEntries(entries);
    return Scaffold(
      appBar: AppBar(title: const Text('수정 이력')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: groups
            .map(
              (group) => _AuditItem(
                icon: group.entry.table == 'events'
                    ? Icons.edit_calendar_outlined
                    : group.entry.table == 'announcements'
                    ? Icons.campaign_outlined
                    : Icons.play_circle_outline_rounded,
                title:
                    '${_auditTableLabel(group.entry.table)} ${_auditActionLabel(group.entry.action)}'
                    '${group.count > 1 ? ' 외 ${group.count - 1}건' : ''}',
                author:
                    '${group.entry.actor} · ${_relativeTime(group.entry.createdAt)}',
                detail:
                    '변경 시각 ${group.entry.createdAt.month}.${group.entry.createdAt.day} ${time(group.entry.createdAt)}',
              ),
            )
            .toList(),
      ),
    );
  }
}

class _AuditGroup {
  const _AuditGroup({required this.entry, required this.count});
  final AuditEntry entry;
  final int count;
}

/// 같은 (테이블, 동작, 담당자)가 1분 안에 연달아 찍히면 한 줄로 묶는다.
/// 일괄 삭제/가져오기처럼 한 번의 조작이 행마다 별도 로그를 남길 때,
/// 완전히 똑같은 줄이 여러 번 나열되는 것처럼 보이던 문제를 없앤다.
List<_AuditGroup> _groupAuditEntries(List<AuditEntry> entries) {
  final groups = <_AuditGroup>[];
  for (final entry in entries) {
    final last = groups.isEmpty ? null : groups.last;
    final sameBurst =
        last != null &&
        last.entry.table == entry.table &&
        last.entry.action == entry.action &&
        last.entry.actor == entry.actor &&
        last.entry.createdAt.difference(entry.createdAt).abs() <
            const Duration(minutes: 1);
    if (sameBurst) {
      groups[groups.length - 1] = _AuditGroup(
        entry: last.entry,
        count: last.count + 1,
      );
    } else {
      groups.add(_AuditGroup(entry: entry, count: 1));
    }
  }
  return groups;
}

String _auditTableLabel(String table) => switch (table) {
  'events' => '일정',
  'announcements' => '공지',
  'videos' => '영상',
  'operation_assignments' => 'IB 운영',
  'homecoming_contacts' => '홈커밍',
  _ => table,
};

String _auditActionLabel(String action) => switch (action) {
  'insert' => '등록',
  'update' => '수정',
  'delete' => '삭제',
  _ => action,
};

String _academicLabel(DateTime date) {
  final monthDay = date.month * 100 + date.day;
  if (monthDay >= 301 && monthDay <= 615) return '${date.year} · 1학기';
  if (monthDay >= 901 && monthDay <= 1214) return '${date.year} · 2학기';
  return '${date.year} · 방학';
}

String _dayId(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.date,
    required this.title,
    required this.place,
    required this.onTap,
  });
  final String date;
  final String title;
  final String place;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: EncbaColors.highlight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            date,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: EncbaColors.deepBlue,
            ),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(place),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    ),
  );
}

class _AuditItem extends StatelessWidget {
  const _AuditItem({
    required this.icon,
    required this.title,
    required this.author,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String author;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: EncbaColors.snuBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    author,
                    style: const TextStyle(
                      color: EncbaColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(detail),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
