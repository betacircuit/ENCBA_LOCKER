part of '../locker_shell.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    final rates = ref.watch(
      lockerControllerProvider.select(
        (state) => state.eventsState.attendanceRates,
      ),
    );
    final homecomingCampaign = ref.watch(
      lockerControllerProvider.select(
        (state) => state.operationsState.homecomingCampaign,
      ),
    );
    return _Page(
      header: _Header(
        eyebrow: 'MY LOCKER',
        title: 'PERSONAL',
        action: IconButton(
          tooltip: '로그아웃',
          onPressed: () => _confirmSignOut(context, ref),
          icon: const Icon(Icons.logout_rounded),
        ),
      ),
      children: [
        const _PwaInstallCard(),
        _ProfileCard(
          name: user.visibleName,
          meta:
              '${user.studentId} · ${user.joinedYear == null ? '가입 연도 미등록' : '${user.joinedYear} 가입'} · #${user.jerseyNumber} ${user.position}',
          teamLabel: user.teamLabel,
          badge: user.badge,
          photoBase64: user.photoBase64,
          leadershipLabel: user.leadershipLabel,
          onTap: () => context.push('/profile/edit'),
        ),
        const SizedBox(height: 12),
        _StatsStrip(rates: rates),
        const SizedBox(height: 24),
        const _SectionHeader(title: '내 메뉴'),
        const SizedBox(height: 10),
        _MenuTile(
          icon: Icons.sports_basketball_outlined,
          title: '농구장 예약',
          subtitle: '71동 · 71-1동 · 900동 예약과 오픈 시간',
          onTap: () => context.push('/reservations'),
        ),
        _MenuTile(
          icon: Icons.groups_2_outlined,
          title: user.canAdminister ? '멤버' : '멤버 디렉토리',
          subtitle: user.canAdminister ? '계정 정보·직책·활성 상태 관리' : '재학·군 휴학 상태 확인',
          onTap: () => context.push('/members'),
        ),
        _MenuTile(
          icon: Icons.fact_check_outlined,
          title: '내 출결 통계',
          subtitle: '내 참석·불참 응답 기록과 참석률',
          onTap: () => _showMyAttendance(context, ref),
        ),
        _MenuTile(
          icon: Icons.bug_report_outlined,
          title: '오류 제보',
          subtitle: '발생한 문제를 개발자에게 보내기',
          onTap: () => context.push('/bug-report'),
        ),
        _MenuTile(
          icon: Icons.assignment_outlined,
          title: 'IB 운영 일정',
          subtitle: '학기 초 업로드된 엑셀 기준',
          onTap: () => context.push('/operations'),
        ),
        _MenuTile(
          icon: Icons.celebration_outlined,
          title: '홈커밍 연락 보드',
          subtitle: homecomingCampaign == null
              ? '관리자가 이번 학기 이벤트를 열기 전입니다'
              : '${homecomingCampaign.eventDate.month}.${homecomingCampaign.eventDate.day} 진행',
          onTap: () => context.push('/homecoming'),
        ),
        _MenuTile(
          icon: Icons.history_rounded,
          title: '수정 이력',
          subtitle: '공지와 일정의 변경 기록',
          onTap: () => context.push('/audit'),
        ),
        if (user.canAdminister) const _AdminSection(),
      ],
    );
  }
}

/// 관리자·주장 전용 섹션. 예전에는 이 기능들의 버튼이 홈커밍·IB 운영
/// 화면 안에 부원용 화면과 섞여 있었다. 그 화면들은 이제 부원이 보는
/// 그대로를 관리자도 보게 두고, 관리 동작은 여기 한곳에 모은다.
class _AdminSection extends ConsumerStatefulWidget {
  const _AdminSection();

  @override
  ConsumerState<_AdminSection> createState() => _AdminSectionState();
}

class _AdminSectionState extends ConsumerState<_AdminSection> {
  bool _operationsImporting = false;

  // 홈커밍 가져오기/내보내기 버튼은 모달 바텀시트 안에 있다. 바텀시트는
  // Navigator 오버레이에 별도로 올라가는 라우트라 이 State의 setState로는
  // 다시 그려지지 않는다. ValueNotifier + ValueListenableBuilder로 만들어
  // 어느 쪽에서 값이 바뀌어도 시트 안의 버튼이 항상 반영되게 한다.
  final _homecomingImporting = ValueNotifier<bool>(false);
  final _homecomingExporting = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    // 홈커밍 캠페인 관리는 이 섹션에서 바로 응답 엑셀/다시 잠그기를
    // 실행할 수 있어야 하므로, 부원처럼 홈커밍 화면을 먼저 열지 않아도
    // 연락망을 미리 읽어 둔다.
    Future.microtask(
      () =>
          ref.read(lockerControllerProvider.notifier).loadHomecomingContacts(),
    );
  }

  @override
  void dispose() {
    _homecomingImporting.dispose();
    _homecomingExporting.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const _SectionHeader(title: '관리자'),
        const SizedBox(height: 10),
        _MenuTile(
          icon: Icons.person_add_alt_1_outlined,
          title: '새 멤버 등록',
          subtitle: '구글 로그인 때 대조하는 가입 명단에 실명을 미리 추가',
          onTap: () => _showMemberEditor(context, ref, null),
        ),
        _MenuTile(
          icon: Icons.badge_outlined,
          title: '멤버 직책 관리',
          subtitle: '역할(관리자·주장·매니저), 벤 감독 같은 표시용 직책, 활성 상태를 수정',
          onTap: () => context.push('/members'),
        ),
        _MenuTile(
          icon: Icons.pending_actions_outlined,
          title: '가입 대기 명단',
          subtitle: '아직 구글 계정으로 가입하지 않은 예비 인원만 모아 보기',
          onTap: () => context.push('/members?pending=1'),
        ),
        _MenuTile(
          icon: Icons.upload_file_outlined,
          title: _operationsImporting ? 'IB 운영표 가져오는 중…' : 'IB 운영표 가져오기',
          subtitle: '학기 초 엑셀로 운영 배정을 새로 등록',
          onTap: _operationsImporting ? () {} : _importOperations,
        ),
        _MenuTile(
          icon: campaign == null
              ? Icons.lock_open_rounded
              : Icons.celebration_outlined,
          title: campaign == null ? '이번 학기 홈커밍 열기' : '홈커밍 캠페인 관리',
          subtitle: campaign == null
              ? '연락 보드를 새로 시작합니다'
              : '엑셀 가져오기 · 응답 엑셀 · 다시 잠그기',
          onTap: campaign == null
              ? _activateCampaign
              : () => _showHomecomingAdmin(campaign, contacts),
        ),
      ],
    );
  }

  Future<void> _importOperations() async {
    setState(() => _operationsImporting = true);
    try {
      final parsed = await IbOperationImportService().pickAndParse();
      if (!mounted || parsed == null) return;
      final selectedAssignees = await _selectOperationAssignees(parsed);
      if (!mounted || selectedAssignees == null) return;
      final selectedRows = parsed.rows
          .where(
            (row) => selectedAssignees.contains(
              (row['assignee_name'] as String?)?.trim() ?? '',
            ),
          )
          .toList(growable: false);
      final result = await ref
          .read(lockerControllerProvider.notifier)
          .importOperations(
            fileName: parsed.fileName,
            academicYear: parsed.academicYear,
            term: parsed.term,
            assignments: selectedRows,
          );
      if (!mounted) return;
      await _showOperationImportResult(result);
    } on FormatException catch (error) {
      if (mounted) {
        await _showOperationImportError(error.message);
      }
    } on Object catch (error) {
      if (mounted) {
        await _showOperationImportError(
          kDebugMode ? '엑셀 오류: $error' : '엑셀 파일을 읽지 못했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _operationsImporting = false);
    }
  }

  Future<Set<String>?> _selectOperationAssignees(
    IbOperationImportResult parsed,
  ) async {
    final members = await ref
        .read(lockerControllerProvider.notifier)
        .loadAllMembersForAccountCheck();
    if (!mounted) return null;
    final memberByName = {for (final member in members) member.name: member};
    final counts = <String, int>{};
    for (final row in parsed.rows) {
      final name = (row['assignee_name'] as String?)?.trim() ?? '';
      if (name.isNotEmpty) {
        counts.update(name, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final names = counts.keys.toList()..sort();
    final selected = names.toSet();
    return showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${parsed.academicYear}-${parsed.term} IB 선택 등록'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${parsed.dateCount}개 날짜 · ${parsed.rows.length}건 · 고정 경기 시간 적용',
                ),
                if (parsed.warnings.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    parsed.warnings.join('\n'),
                    style: const TextStyle(
                      color: EncbaColors.late,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(() {
                        selected
                          ..clear()
                          ..addAll(names);
                      }),
                      child: const Text('전체 선택'),
                    ),
                    TextButton(
                      onPressed: () => setDialogState(() {
                        selected
                          ..clear()
                          ..addAll(
                            names.where((name) {
                              final member = memberByName[name];
                              return member?.hasRegisteredAccount == true &&
                                  member?.isActive == true;
                            }),
                          );
                      }),
                      child: const Text('활성 계정만'),
                    ),
                  ],
                ),
                SizedBox(
                  height: 320,
                  child: ListView(
                    children: names
                        .map((name) {
                          final member = memberByName[name];
                          final status =
                              member == null || !member.hasRegisteredAccount
                              ? '계정 미등록'
                              : member.isActive
                              ? '활성 계정'
                              : '비활성 계정';
                          return CheckboxListTile(
                            dense: true,
                            value: selected.contains(name),
                            title: Text('$name · ${counts[name]}건'),
                            subtitle: Text(status),
                            onChanged: (checked) => setDialogState(() {
                              checked == true
                                  ? selected.add(name)
                                  : selected.remove(name);
                            }),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                const Text(
                  '선택한 멤버의 일정만 계정에 등록합니다. 같은 학기의 기존 엑셀 배정은 선택 결과로 교체됩니다. 1경기 13:00–14:00, 2경기 14:10–15:10, 3경기 15:20–16:20으로 고정됩니다.',
                  style: TextStyle(color: EncbaColors.muted, fontSize: 12),
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
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, Set.of(selected)),
              child: Text('${selected.length}명 등록'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOperationImportResult(
    ({int imported, int unmatched})? result,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(result == null ? '가져오기 실패' : 'IB 운영 일정 등록 완료'),
      content: Text(
        result == null
            ? 'IB 운영표를 가져오지 못했습니다.'
            : '${result.imported}건을 저장했습니다.\n'
                  '계정 미등록 또는 이름이 맞지 않아 연결되지 않은 일정은 ${result.unmatched}건입니다.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );

  Future<void> _showOperationImportError(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('엑셀 가져오기 실패'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );

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

  Future<void> _showHomecomingAdmin(
    HomecomingCampaign campaign,
    List<HomecomingContact> contacts,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              campaign.title,
              style: Theme.of(sheetContext).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${campaign.eventDate.month}월 ${campaign.eventDate.day}일 · '
              '${campaign.startsAt.substring(0, 5)}–${campaign.endsAt.substring(0, 5)} · '
              '${campaign.venue}',
              style: const TextStyle(color: EncbaColors.muted),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<bool>(
              valueListenable: _homecomingImporting,
              builder: (context, importing, _) => FilledButton.icon(
                onPressed: importing ? null : _importHomecomingExcel,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(importing ? '가져오는 중…' : '엑셀 가져오기'),
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<bool>(
              valueListenable: _homecomingExporting,
              builder: (context, exporting, _) => OutlinedButton.icon(
                onPressed: exporting || contacts.isEmpty
                    ? null
                    : () => _exportHomecomingExcel(campaign, contacts),
                icon: exporting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(exporting ? '만드는 중…' : '응답 엑셀'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(sheetContext);
                await _lockCampaign(campaign);
              },
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text('다시 잠그기'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _importHomecomingExcel() async {
    _homecomingImporting.value = true;
    try {
      final parsed = await HomecomingImportService().pickAndParse();
      if (parsed == null || !mounted) return;
      final selectedAssignees = await _selectHomecomingAssignees(
        parsed.rows,
        parsed.sheetName,
        parsed.warnings,
      );
      if (!mounted || selectedAssignees == null) return;
      final selectedRows = parsed.rows
          .where(
            (row) => selectedAssignees.contains(
              (row['assigned_to_name'] as String?)?.trim() ?? '담당 미지정',
            ),
          )
          .toList(growable: false);
      final ok = await ref
          .read(lockerControllerProvider.notifier)
          .importHomecomingContacts(
            fileName: parsed.fileName,
            contacts: selectedRows,
          );
      if (mounted && !ok) {
        await _showHomecomingImportError('홈커밍 연락망을 가져오지 못했습니다.');
      }
    } on FormatException catch (error) {
      if (mounted) {
        await _showHomecomingImportError(error.message);
      }
    } on Object catch (error) {
      if (mounted) {
        await _showHomecomingImportError(
          kDebugMode ? '엑셀 오류: $error' : '엑셀 파일을 읽지 못했습니다.',
        );
      }
    } finally {
      _homecomingImporting.value = false;
    }
  }

  Future<Set<String>?> _selectHomecomingAssignees(
    List<Map<String, dynamic>> rows,
    String sheetName,
    List<String> warnings,
  ) async {
    final members = await ref
        .read(lockerControllerProvider.notifier)
        .loadAllMembersForAccountCheck();
    if (!mounted) return null;
    final memberByName = {for (final member in members) member.name: member};
    final counts = <String, int>{};
    for (final row in rows) {
      final name = (row['assigned_to_name'] as String?)?.trim();
      final key = name == null || name.isEmpty ? '담당 미지정' : name;
      counts.update(key, (value) => value + 1, ifAbsent: () => 1);
    }
    final names = counts.keys.toList()..sort();
    final selected = names.toSet();
    return showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('$sheetName · 담당자 선택 등록'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${rows.length}명의 선배 연락처를 읽었습니다.'),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    warnings.join('\n'),
                    style: const TextStyle(
                      color: EncbaColors.late,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(() {
                        selected
                          ..clear()
                          ..addAll(names);
                      }),
                      child: const Text('전체 선택'),
                    ),
                    TextButton(
                      onPressed: () => setDialogState(() {
                        selected
                          ..clear()
                          ..addAll(
                            names.where((name) {
                              final member = memberByName[name];
                              return member?.hasRegisteredAccount == true &&
                                  member?.isActive == true;
                            }),
                          );
                      }),
                      child: const Text('활성 계정만'),
                    ),
                  ],
                ),
                SizedBox(
                  height: 300,
                  child: ListView(
                    shrinkWrap: true,
                    children: names
                        .map((name) {
                          final member = memberByName[name];
                          final status =
                              member == null || !member.hasRegisteredAccount
                              ? '계정 미등록'
                              : member.isActive
                              ? '활성 계정'
                              : '비활성 계정';
                          return CheckboxListTile(
                            dense: true,
                            value: selected.contains(name),
                            title: Text('$name · ${counts[name]}명'),
                            subtitle: Text(status),
                            onChanged: (checked) => setDialogState(() {
                              checked == true
                                  ? selected.add(name)
                                  : selected.remove(name);
                            }),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                const Text(
                  '선택한 담당자 그룹만 새 연락망으로 등록됩니다. 비활성·미등록 계정은 앱으로 배정이 전달되지 않을 수 있습니다.',
                  style: TextStyle(color: EncbaColors.muted, fontSize: 12),
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
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, Set.of(selected)),
              child: Text('${selected.length}개 그룹 등록'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHomecomingImportError(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('가져오기 실패'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );

  Future<void> _exportHomecomingExcel(
    HomecomingCampaign campaign,
    List<HomecomingContact> contacts,
  ) async {
    _homecomingExporting.value = true;
    try {
      final saved = await HomecomingExportService().export(
        campaign: campaign,
        contacts: contacts,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(saved ? '홈커밍 응답 엑셀을 저장했습니다.' : '파일 저장을 취소했습니다.'),
          ),
        );
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA homecoming export failed: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('홈커밍 응답 엑셀을 만들지 못했습니다.')));
    } finally {
      _homecomingExporting.value = false;
    }
  }

  Future<void> _lockCampaign(HomecomingCampaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('홈커밍을 다시 잠글까요?'),
        content: const Text('연락 기록은 삭제되지 않으며, 관리자가 다시 열기 전까지 연락 보드가 숨겨집니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('잠그기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final locked = await ref
        .read(lockerControllerProvider.notifier)
        .deactivateHomecomingCampaign(campaign.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(locked ? '홈커밍 연락 보드를 잠갔습니다.' : '홈커밍을 잠그지 못했습니다.')),
      );
  }
}

class BugReportScreen extends ConsumerStatefulWidget {
  const BugReportScreen({super.key});

  @override
  ConsumerState<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends ConsumerState<BugReportScreen> {
  final _controller = TextEditingController();
  bool _opening = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('오류 제보')),
    resizeToAvoidBottomInset: true,
    body: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '어떤 문제가 있었나요?',
              style: TextStyle(
                fontFamily: 'Jua',
                fontSize: 27,
                color: EncbaColors.navy,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              '작성자와 실행 환경은 메일 본문에 자동으로 포함됩니다.',
              style: TextStyle(color: EncbaColors.muted),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                scrollPadding: const EdgeInsets.only(bottom: 120),
                decoration: const InputDecoration(
                  hintText: '오류가 난 화면과 직전에 한 행동을 적어 주세요.',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _opening ? null : _openMail,
              icon: _opening
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.mail_outline_rounded),
              label: Text(_opening ? '오류 제보 전송 중…' : '오류 제보 보내기'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _openMail() async {
    final report = _controller.text.trim();
    if (report.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('오류 내용을 입력해 주세요.')));
      return;
    }
    setState(() => _opening = true);
    final user = ref.read(authControllerProvider).user;
    final body =
        '''작성자: ${user?.visibleName ?? '확인 불가'}
학번: ${user?.studentId ?? '확인 불가'}
계정: ${user?.email ?? '확인 불가'}
실행 환경: ${kIsWeb ? '웹' : defaultTargetPlatform.name}

[오류 내용]
$report''';
    try {
      await sendErrorReport(client: Supabase.instance.client, body: body);
      if (!mounted) return;
      setState(() => _opening = false);
      _controller.clear();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('오류 제보를 전송했습니다.')));
      return;
    } on Object {
      // 서버 메일 설정 전이거나 일시 장애면 작성 내용이 사라지지 않도록 메일 앱으로 넘긴다.
    }
    final uri = buildErrorReportUri(body: body, isWeb: kIsWeb);
    var opened = false;
    try {
      opened = await launchUrl(
        uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } on Object {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _opening = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? kIsWeb
                    ? '자동 전송에 실패해 Gmail 작성창을 열었습니다.'
                    : '자동 전송에 실패해 메일 앱을 열었습니다.'
              : kIsWeb
              ? 'Gmail을 열지 못했습니다. 팝업 차단을 확인해 주세요.'
              : '메일 앱을 열지 못했습니다. legojmon@snu.ac.kr로 보내 주세요.',
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.meta,
    required this.teamLabel,
    required this.badge,
    required this.photoBase64,
    required this.leadershipLabel,
    required this.onTap,
  });
  final String name;
  final String meta;
  final String teamLabel;
  final String? badge;
  final String? photoBase64;
  final String? leadershipLabel;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            _Avatar(name: name, size: 62, photoBase64: photoBase64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 7),
                        _SmallBadge(badge!),
                      ],
                      if (leadershipLabel != null) ...[
                        const SizedBox(width: 7),
                        _SmallBadge(leadershipLabel!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: const TextStyle(
                      color: EncbaColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    teamLabel,
                    style: const TextStyle(
                      color: EncbaColors.snuBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 20),
          ],
        ),
      ),
    ),
  );
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.rates});
  final AttendanceRates rates;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Stat(value: '${rates.training}%', label: '훈련'),
          const _Rule(),
          _Stat(value: '${rates.morning}%', label: '아농'),
          const _Rule(),
          _Stat(value: '${rates.game}%', label: '경기'),
        ],
      ),
    ),
  );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        leading: Icon(icon, color: EncbaColors.snuBlue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    ),
  );
}

Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('로그아웃할까요?'),
      content: const Text('오프라인 일정과 계정은 이 기기에 남아 있습니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('로그아웃'),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await ref.read(authControllerProvider.notifier).signOut();
  }
}
