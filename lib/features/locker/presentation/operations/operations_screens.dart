part of '../locker_shell.dart';

class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});

  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  bool _importing = false;

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
      lockerControllerProvider.select((state) => state.operationsState),
    );
    final operations = operationsState.operations;
    final pendingRequests = operationsState.operationSwapRequests
        .where((request) => request.status == 'pending')
        .toList(growable: false);
    final exchangeTargets = operationsState.operationExchangeBoard
        .where((assignment) => !assignment.isMine)
        .toList(growable: false);
    final isAdmin =
        ref.watch(authControllerProvider).user?.leadershipRole == 'admin';
    return Scaffold(
      appBar: AppBar(
        title: const Text('IB 운영 일정'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'IB 운영표 엑셀 가져오기',
              onPressed: _importing ? null : _importExcel,
              icon: _importing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
            ),
        ],
      ),
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
                date: '${item.start.month}.${item.start.day}',
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
                    date: '${item.start.month}.${item.start.day}',
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('교환할 내 운영 일정이 없습니다.')));
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
                  '${target.assigneeName} · ${target.start.month}.${target.start.day} ${time(target.start)}',
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
                            '${item.start.month}.${item.start.day} ${time(item.start)} · ${item.title}',
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
    ScaffoldMessenger.of(context).showSnackBar(
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
    ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _importExcel() async {
    setState(() => _importing = true);
    try {
      final parsed = await IbOperationImportService().pickAndParse();
      if (!mounted || parsed == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${parsed.academicYear}-${parsed.term} IB 운영표'),
          content: SingleChildScrollView(
            child: Text(
              '${parsed.dateCount}개 날짜에서 ${parsed.rows.length}건을 읽었습니다.\n'
              '원본 시간 ${parsed.explicitTimeCount}건 · 기본 시간 ${parsed.defaultTimeCount}건\n\n'
              '${parsed.warnings.isEmpty ? '' : '${parsed.warnings.join('\n')}\n\n'}'
              '같은 학기의 기존 엑셀 배정은 교체됩니다. 표에 시간이 없는 경우 '
              '1경기 11시, 2경기 13시, 3경기 15시로 적용합니다.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('가져오기'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final result = await ref
          .read(lockerControllerProvider.notifier)
          .importOperations(
            fileName: parsed.fileName,
            academicYear: parsed.academicYear,
            term: parsed.term,
            assignments: parsed.rows,
          );
      if (!mounted) return;
      final message = result == null
          ? 'IB 운영표를 가져오지 못했습니다.'
          : '${result.imported}건 저장 · 계정 미연결 ${result.unmatched}건';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kDebugMode ? '엑셀 오류: $error' : '엑셀 파일을 읽지 못했습니다.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(
      lockerControllerProvider.select(
        (state) => state.operationsState.auditEntries,
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('수정 이력')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: entries
            .map(
              (entry) => _AuditItem(
                icon: entry.table == 'events'
                    ? Icons.edit_calendar_outlined
                    : entry.table == 'announcements'
                    ? Icons.campaign_outlined
                    : Icons.play_circle_outline_rounded,
                title:
                    '${_auditTableLabel(entry.table)} ${_auditActionLabel(entry.action)}',
                author: '${entry.actor} · ${_relativeTime(entry.createdAt)}',
                detail:
                    '변경 시각 ${entry.createdAt.month}.${entry.createdAt.day} ${time(entry.createdAt)}',
              ),
            )
            .toList(),
      ),
    );
  }
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
