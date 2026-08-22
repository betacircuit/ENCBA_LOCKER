part of '../locker_shell.dart';

class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});

  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
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
        ],
      ),
    );
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
  final VoidCallback onTap;
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
