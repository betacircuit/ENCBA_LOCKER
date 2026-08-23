part of '../locker_shell.dart';

class HomecomingScreen extends ConsumerStatefulWidget {
  const HomecomingScreen({super.key});
  @override
  ConsumerState<HomecomingScreen> createState() => _HomecomingScreenState();
}

class _HomecomingScreenState extends ConsumerState<HomecomingScreen> {
  int _assigneeIndex = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () =>
          ref.read(lockerControllerProvider.notifier).loadHomecomingContacts(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    final homecomingState = ref.watch(
      lockerControllerProvider.select(
        (state) => (
          campaign: state.operationsState.homecomingCampaign,
          contacts: state.operationsState.homecomingContacts,
        ),
      ),
    );
    final campaign = homecomingState.campaign;
    final contacts = homecomingState.contacts;
    final assignees =
        contacts
            .map((item) => item.assignedToName?.trim() ?? '')
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final assigneePages = isAdmin ? ['전체', ...assignees] : assignees;
    final safeAssigneeIndex = assigneePages.isEmpty
        ? 0
        : _assigneeIndex.clamp(0, assigneePages.length - 1);
    final selectedAssignee = assigneePages.isEmpty
        ? null
        : assigneePages[safeAssigneeIndex];
    final visibleContacts = selectedAssignee == null || selectedAssignee == '전체'
        ? contacts
        : contacts
              .where((item) => item.assignedToName == selectedAssignee)
              .toList(growable: false);
    final complete = contacts.where((item) => item.handled).length;
    return Scaffold(
      appBar: AppBar(title: const Text('홈커밍 연락 보드')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (campaign == null) ...[
            const SizedBox(height: 70),
            const Icon(
              Icons.lock_outline_rounded,
              size: 42,
              color: EncbaColors.muted,
            ),
            const SizedBox(height: 16),
            Text(
              '홈커밍 준비 기간이 아닙니다',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              '관리자가 이번 학기 캠페인을 열면 연락 보드가 활성화됩니다.',
              textAlign: TextAlign.center,
            ),
            if (isAdmin) ...[
              const SizedBox(height: 12),
              const Text(
                '개인 탭의 관리자 섹션에서 열 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: EncbaColors.muted, fontSize: 12),
              ),
            ],
          ] else ...[
            Text(campaign.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${campaign.eventDate.month}월 ${campaign.eventDate.day}일 · ${campaign.startsAt.substring(0, 5)}–${campaign.endsAt.substring(0, 5)} · ${campaign.venue}',
            ),
            const SizedBox(height: 18),
            Text(
              '$complete / ${contacts.length} 응답 처리',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: contacts.isEmpty ? 0 : complete / contacts.length,
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _showManuals,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('연락 매뉴얼'),
            ),
            if (isAdmin) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => _showAddContactDialog(campaign),
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('선배 직접 추가'),
              ),
            ],
            if (isAdmin) ...[
              const SizedBox(height: 6),
              const Text(
                '엑셀 가져오기·응답 엑셀·다시 잠그기는 개인 탭의 관리자 섹션에 있습니다.',
                style: TextStyle(color: EncbaColors.muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            if (assigneePages.isNotEmpty) ...[
              Card(
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '이전 담당자',
                      onPressed: safeAssigneeIndex == 0
                          ? null
                          : () => setState(() => _assigneeIndex--),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '$selectedAssignee · ${visibleContacts.length}명',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '다음 담당자',
                      onPressed: safeAssigneeIndex >= assigneePages.length - 1
                          ? null
                          : () => setState(() => _assigneeIndex++),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            ...visibleContacts.map(
              (contact) => _HomecomingContactListTile(
                contact: contact,
                onTap: () => _showContact(contact, campaign, isAdmin),
                onDelete: isAdmin
                    ? () => _confirmDeleteContact(contact)
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showContact(
    HomecomingContact contact,
    HomecomingCampaign campaign,
    bool isAdmin,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _HomecomingContactDetailSheet(
      contactId: contact.id,
      campaign: campaign,
      isAdmin: isAdmin,
      onSendSms: _sendSms,
    ),
  );

  /// 관리자가 엑셀 없이 선배를 한 명 직접 추가한다.
  Future<void> _showAddContactDialog(HomecomingCampaign campaign) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final generation = TextEditingController();
    var assignedToId = '';
    var assignedToName = '';
    final members = await ref
        .read(lockerControllerProvider.notifier)
        .loadAllMembersForAccountCheck();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('선배 연락처 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '선배 성함 *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '휴대전화 *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: generation,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '기수(학번, 선택)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: assignedToId.isEmpty ? null : assignedToId,
                  decoration: const InputDecoration(labelText: '담당 부원 (선택)'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('담당 미지정')),
                    for (final member in members)
                      if (member.id != null && member.isActive)
                        DropdownMenuItem(
                          value: member.id,
                          child: Text(member.name),
                        ),
                  ],
                  onChanged: (value) => setDialogState(() {
                    assignedToId = value ?? '';
                    assignedToName = members
                        .where((member) => member.id == value)
                        .map((member) => member.name)
                        .firstOrNull ?? '';
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty || phone.text.trim().isEmpty
                  ? null
                  : () async {
                      final saved = await ref
                          .read(lockerControllerProvider.notifier)
                          .addHomecomingContact(
                            name: name.text.trim(),
                            phone: phone.text.trim(),
                            generation: int.tryParse(generation.text.trim()),
                            assignedToId: assignedToId.isEmpty
                                ? null
                                : assignedToId,
                            assignedToName: assignedToName.isEmpty
                                ? null
                                : assignedToName,
                          );
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              saved ? '선배를 추가했습니다.' : '추가하지 못했습니다.',
                            ),
                          ),
                        );
                    },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteContact(HomecomingContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${contact.name} 선배를 삭제할까요?'),
        content: const Text('연락 기록도 함께 사라지며 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleted = await ref
        .read(lockerControllerProvider.notifier)
        .deleteHomecomingContact(contact.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(deleted ? '삭제했습니다.' : '삭제하지 못했습니다.')),
      );
  }

  Future<void> _sendSms(
    HomecomingContact contact,
    HomecomingCampaign campaign,
  ) async {
    final user = ref.read(authControllerProvider).user!;
    final studentYear = user.studentId.replaceAll('학번', '');
    final body =
        '${contact.name} 선배님 안녕하십니까? 서울대학교 공대농구동아리 엔크바 $studentYear학번 ${user.name}입니다.\n'
        '다름이 아니라, 이번 ${campaign.term}학기 엔크바 홈커밍 데이가 ${campaign.eventDate.month}월 ${campaign.eventDate.day}일에 예정되어 있습니다. 참석 확인 차 전화드렸는데 연락이 안되셔서 문자 드립니다.\n'
        '혹시 홈커밍 데이 때 참석 가능하실까요?\n\n감사합니다.';
    // `Uri(queryParameters: ...)` percent-encodes using
    // application/x-www-form-urlencoded rules, which turns every space into
    // a literal `+`. SMS bodies aren't form data, so that leaves "+" signs
    // in the text message instead of spaces/line breaks. Build the query
    // string manually with `Uri.encodeComponent`, which encodes spaces as
    // `%20` and newlines as `%0A`, so the Messages app renders real spaces.
    final uri = Uri.parse(
      'sms:${Uri.encodeComponent(contact.phone)}?body=${Uri.encodeComponent(body)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showManuals() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(22),
          children: const [
            Text('전화 매뉴얼', style: TextStyle(fontFamily: 'Jua', fontSize: 25)),
            SizedBox(height: 12),
            SelectableText(
              '안녕하세요, 혹시 XXX 선배님 맞으십니까?\n선배님 안녕하십니까, 서울대학교 공대 농구동아리 엔크바 XX학번 XXX입니다.\n다름이 아니라 이번 엔크바 홈커밍 데이가 예정되어 있습니다. 혹시 참석 가능하십니까?\n\n참석: 감사합니다 선배님. 그때 뵙겠습니다. 주차권이 필요하신지, 행사 일주일 전에 다시 연락드려도 되는지 여쭤봅니다.\n\n미정: 다음 주에 다시 확인전화 드려도 괜찮으신지 여쭤봅니다.\n\n불참: 다음 홈커밍 행사에서는 꼭 뵈었으면 좋겠습니다. 감사합니다.\n\n회식 장소: 현재 물색 중이며 확정되는 대로 안내드립니다.',
            ),
            SizedBox(height: 24),
            Text('답장 매뉴얼', style: TextStyle(fontFamily: 'Jua', fontSize: 25)),
            SizedBox(height: 12),
            SelectableText(
              '장소/시간: 서울대학교 기숙사체육관에서 진행되며 이후 뒷풀이 예정입니다.\n\n참석: 감사합니다 선배님. 주차권이 필요한지 여쭤보고 일주일 전 확인 연락 동의를 받습니다.\n\n불참: 다음 홈커밍 데이에는 꼭 뵈었으면 좋겠습니다.\n\n회식: 아직 정해지지 않았고 밴드 공지 후 안내드립니다.',
            ),
          ],
        ),
      ),
    );
  }
}

class _HomecomingContactListTile extends StatelessWidget {
  const _HomecomingContactListTile({
    required this.contact,
    required this.onTap,
    this.onDelete,
  });

  final HomecomingContact contact;
  final VoidCallback onTap;

  /// 관리자에게만 전달된다. null이면 삭제 버튼을 보여주지 않는다.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _homecomingStatusColor(
              contact.status,
            ).withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Text(
            contact.generationCode.isEmpty ? '--' : contact.generationCode,
            style: TextStyle(
              color: _homecomingStatusColor(contact.status),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(
          '${contact.name} 선배님 (${contact.statusLabel})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: onDelete == null
            ? const Icon(Icons.chevron_right_rounded)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '삭제',
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: EncbaColors.absent,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
      ),
    ),
  );
}

class _HomecomingContactDetailSheet extends ConsumerWidget {
  const _HomecomingContactDetailSheet({
    required this.contactId,
    required this.campaign,
    required this.isAdmin,
    required this.onSendSms,
  });

  final String contactId;
  final HomecomingCampaign campaign;
  final bool isAdmin;
  final Future<void> Function(HomecomingContact, HomecomingCampaign) onSendSms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(
      lockerControllerProvider.select((state) {
        for (final item in state.operationsState.homecomingContacts) {
          if (item.id == contactId) return item;
        }
        return null;
      }),
    );
    if (contact == null) {
      return const SizedBox(
        height: 240,
        child: Center(child: Text('연락 정보를 찾지 못했습니다.')),
      );
    }
    final callPhone = contact.phone.isNotEmpty
        ? contact.phone
        : contact.homeOrOfficePhone ?? '';
    final phoneLabel = callPhone.isEmpty ? '연락처 없음' : callPhone;
    return FractionallySizedBox(
      heightFactor: .92,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: EncbaColors.line,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${contact.name} 선배님',
                        style: const TextStyle(
                          fontFamily: 'Jua',
                          fontSize: 25,
                          color: EncbaColors.navy,
                        ),
                      ),
                      Text(
                        '${contact.generationLabel} · $phoneLabel',
                        style: const TextStyle(color: EncbaColors.muted),
                      ),
                      if (isAdmin &&
                          contact.assignedToName?.trim().isNotEmpty == true)
                        Text(
                          '담당 ${contact.assignedToName}',
                          style: const TextStyle(
                            color: EncbaColors.snuBlue,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: callPhone.isEmpty
                            ? null
                            : () => _launch(context, 'tel:$callPhone'),
                        icon: const Icon(Icons.phone_outlined),
                        label: const Text('전화'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: contact.phone.isEmpty
                            ? null
                            : () => onSendSms(contact, campaign),
                        icon: const Icon(Icons.sms_outlined),
                        label: const Text('문자'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(contact.status),
                  initialValue: contact.status,
                  decoration: const InputDecoration(labelText: '응답 상태'),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('미연락')),
                    DropdownMenuItem(
                      value: 'contacted',
                      child: Text('미정 · 재연락'),
                    ),
                    DropdownMenuItem(value: 'confirmed', child: Text('참석')),
                    DropdownMenuItem(value: 'declined', child: Text('불참')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _save(
                      ref,
                      contact.copyWith(
                        status: value,
                        parkingRequired: value == 'confirmed'
                            ? contact.parkingRequired
                            : false,
                        parkingRegistered: value == 'confirmed'
                            ? contact.parkingRegistered
                            : false,
                        followUpAllowed: value == 'contacted'
                            ? true
                            : contact.followUpAllowed,
                        followUpOn: value == 'contacted'
                            ? DateTime.now().add(const Duration(days: 7))
                            : contact.followUpOn,
                      ),
                    );
                  },
                ),
                if (contact.canRequestParking) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: contact.parkingRequired ?? false,
                    title: const Text('주차권 필요'),
                    onChanged: (value) =>
                        _save(ref, contact.copyWith(parkingRequired: value)),
                  ),
                  if (contact.parkingRequired == true)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: contact.parkingRegistered,
                      title: const Text('주차권 처리 완료'),
                      onChanged: (value) => _save(
                        ref,
                        contact.copyWith(parkingRegistered: value),
                      ),
                    ),
                ],
                if (contact.followUpOn != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '다시 연락: ${contact.followUpOn!.month}.${contact.followUpOn!.day}',
                    style: const TextStyle(color: EncbaColors.late),
                  ),
                ],
                const SizedBox(height: 12),
                if (contact.notes?.trim().isNotEmpty == true)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: EncbaColors.highlight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(contact.notes!),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _editNotes(context, ref, contact),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(
                      contact.notes?.trim().isNotEmpty == true
                          ? '메모 수정'
                          : '메모 추가',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(WidgetRef ref, HomecomingContact contact) => ref
      .read(lockerControllerProvider.notifier)
      .updateHomecomingContact(contact);

  Future<void> _editNotes(
    BuildContext context,
    WidgetRef ref,
    HomecomingContact contact,
  ) async {
    var notes = contact.notes ?? '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${contact.name} 선배 연락 기록'),
        content: TextFormField(
          initialValue: notes,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          maxLength: 2000,
          onChanged: (value) => notes = value,
          decoration: const InputDecoration(hintText: '통화·답장 내용을 기록해 주세요.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, notes.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (value != null) await _save(ref, contact.copyWith(notes: value));
  }
}

Color _homecomingStatusColor(String status) => switch (status) {
  'confirmed' => EncbaColors.attending,
  'contacted' => EncbaColors.late,
  'declined' => EncbaColors.muted,
  _ => EncbaColors.snuBlue,
};
