part of '../locker_shell.dart';

class HomecomingScreen extends ConsumerStatefulWidget {
  const HomecomingScreen({super.key});
  @override
  ConsumerState<HomecomingScreen> createState() => _HomecomingScreenState();
}

class _HomecomingScreenState extends ConsumerState<HomecomingScreen> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        ref.watch(authControllerProvider).user?.leadershipRole == 'admin';
    final operationsState = ref.watch(
      lockerControllerProvider.select((state) => state.operationsState),
    );
    final campaign = operationsState.homecomingCampaign;
    final contacts = operationsState.homecomingContacts;
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
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _activateCampaign,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('이번 학기 홈커밍 열기'),
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showManuals,
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('연락 매뉴얼'),
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _importing ? null : _importExcel,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(_importing ? '가져오는 중…' : '엑셀 가져오기'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            ...contacts.map((contact) {
              final callPhone = contact.phone.isNotEmpty
                  ? contact.phone
                  : contact.homeOrOfficePhone ?? '';
              final phoneLabel = callPhone.isEmpty ? '연락처 없음' : callPhone;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${contact.name} 선배',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                    ),
                                  ),
                                  Text(
                                    '${contact.generation == null ? '학번 미상' : '${contact.generation}학번'} · $phoneLabel',
                                    style: const TextStyle(
                                      color: EncbaColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '전화',
                              onPressed: callPhone.isEmpty
                                  ? null
                                  : () => _launch('tel:$callPhone'),
                              icon: const Icon(Icons.phone_outlined),
                            ),
                            IconButton(
                              tooltip: '문자',
                              onPressed: contact.phone.isEmpty
                                  ? null
                                  : () => _sendSms(contact, campaign),
                              icon: const Icon(Icons.sms_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: contact.status,
                          decoration: const InputDecoration(labelText: '응답 상태'),
                          items: const [
                            DropdownMenuItem(
                              value: 'pending',
                              child: Text('미연락'),
                            ),
                            DropdownMenuItem(
                              value: 'contacted',
                              child: Text('미정 · 재연락'),
                            ),
                            DropdownMenuItem(
                              value: 'confirmed',
                              child: Text('참석'),
                            ),
                            DropdownMenuItem(
                              value: 'declined',
                              child: Text('불참'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              _saveContact(
                                contact.copyWith(
                                  status: value,
                                  followUpAllowed: value == 'contacted'
                                      ? true
                                      : contact.followUpAllowed,
                                  followUpOn: value == 'contacted'
                                      ? DateTime.now().add(
                                          const Duration(days: 7),
                                        )
                                      : contact.followUpOn,
                                ),
                              );
                            }
                          },
                        ),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: contact.parkingRequired ?? false,
                          title: const Text('주차권 필요'),
                          onChanged: (value) => _saveContact(
                            contact.copyWith(parkingRequired: value),
                          ),
                        ),
                        if (contact.parkingRequired == true)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: contact.parkingRegistered,
                            title: const Text('주차권 처리 완료'),
                            onChanged: (value) => _saveContact(
                              contact.copyWith(parkingRegistered: value),
                            ),
                          ),
                        if (contact.followUpOn != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '다시 연락: ${contact.followUpOn!.month}.${contact.followUpOn!.day}',
                              style: const TextStyle(color: EncbaColors.late),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _editContactNotes(contact),
                            icon: const Icon(Icons.edit_note_rounded),
                            label: Text(
                              contact.notes?.trim().isNotEmpty == true
                                  ? '기록 보기'
                                  : '메모 추가',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _saveContact(HomecomingContact contact) async {
    await ref
        .read(lockerControllerProvider.notifier)
        .updateHomecomingContact(contact);
  }

  Future<void> _editContactNotes(HomecomingContact contact) async {
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
    if (value != null) await _saveContact(contact.copyWith(notes: value));
  }

  Future<void> _activateCampaign() async {
    final now = DateTime.now();
    final term = now.month >= 9 ? 2 : 1;
    final eventDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (eventDate == null || !mounted) return;
    await ref
        .read(lockerControllerProvider.notifier)
        .activateHomecomingCampaign(
          academicYear: now.year,
          term: term,
          eventDate: eventDate,
          startsAt: '14:00',
          endsAt: '18:00',
          venue: '서울대학교 기숙사체육관',
        );
  }

  Future<void> _importExcel() async {
    setState(() => _importing = true);
    try {
      final parsed = await HomecomingImportService().pickAndParse();
      if (parsed == null || !mounted) return;
      final details = <String>[
        '${parsed.sheetName} 시트에서 ${parsed.rows.length}명을 읽었습니다.',
        ...parsed.warnings,
        '',
        '현재 캠페인의 기존 연락망은 새 명단으로 교체됩니다.',
      ].join('\n');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('홈커밍 연락망 확인'),
          content: SingleChildScrollView(child: Text(details)),
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
      final ok = await ref
          .read(lockerControllerProvider.notifier)
          .importHomecomingContacts(
            fileName: parsed.fileName,
            contacts: parsed.rows,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? '${parsed.rows.length}명을 가져왔습니다.' : '가져오지 못했습니다.',
            ),
          ),
        );
      }
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
    final uri = Uri(
      scheme: 'sms',
      path: contact.phone,
      queryParameters: {'body': body},
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
