part of '../locker_shell.dart';

/// 멤버 상태(status) 코드를 화면에 보여줄 한글 라벨로 바꾼다.
String _statusLabel(String status) => switch (status) {
  'MILITARY_LEAVE' => '군 휴학',
  'EXCHANGE_STUDENT' => '교환학생',
  'STUDY_ABROAD' => '유학',
  'GRADUATED' => '졸업',
  'INACTIVE' => '비활동',
  'OB' => 'OB',
  _ => '재학',
};

class MemberDirectoryScreen extends ConsumerStatefulWidget {
  const MemberDirectoryScreen({super.key, this.startWithPendingOnly = false});

  /// "가입 대기 명단" 메뉴에서 열 때 true. 비활성(가입 대기) 필터를 켠
  /// 상태로 시작해 관리자가 바로 예비 인원을 볼 수 있게 한다.
  final bool startWithPendingOnly;

  @override
  ConsumerState<MemberDirectoryScreen> createState() =>
      _MemberDirectoryScreenState();
}

class _MemberDirectoryScreenState extends ConsumerState<MemberDirectoryScreen> {
  String query = '';
  int _searchRevision = 0;

  /// 기본 정렬은 가나다순. 학번순·가입 연도순은 드롭다운으로 고른다.
  _MemberSort _sort = _MemberSort.name;
  bool _showMilitary = false;
  late bool _showInactive = widget.startWithPendingOnly;
  bool _reservationOnly = false;
  bool _freshmenOnly = false;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final membersState = ref.watch(
      lockerControllerProvider.select((state) => state.membersState),
    );
    final isAdmin =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    final list = membersState.members.where((member) {
      // "군대"/"비활성" 칩은 켜졌을 때 해당 조건에 맞는 사람만 남기는
      // 배타적 필터다(켰다고 다른 사람까지 같이 보이면 안 된다). 꺼져 있을 때는
      // 활동 부원만 보인다. 군 휴학·교환학생·유학·비활동은 모두 비활성으로
      // 취급하므로 비활성 칩을 켜야 이 사람들이 따로 모여서 보인다.
      final isMilitary = member.status == 'MILITARY_LEAVE';
      final inactive = !member.isActiveMember;
      // 군대 칩이 켜져 있으면 군휴학 인원 외에는 모두 제외하고, 비활성 칩이
      // 켜져 있으면 휴면·이탈 인원(군 휴학·교환학생·유학·비활동 포함)만
      // 남긴다. 둘 다 꺼져 있으면 활동 부원만 보인다.
      if (_showMilitary && !isMilitary) return false;
      if (!_showMilitary && _showInactive != inactive) {
        return false;
      }
      if (_reservationOnly && !member.isReservationManager) return false;
      if (_freshmenOnly && !member.isFreshman) return false;
      return true;
    }).toList()..sort(_compareMembers);
    // 동명이인이 있으면 타일 제목 옆에 학번을 붙여 서로 구분하게 한다.
    final nameCounts = <String, int>{};
    for (final member in list) {
      nameCounts[member.name] = (nameCounts[member.name] ?? 0) + 1;
    }
    final duplicateNames = <String>{
      for (final entry in nameCounts.entries)
        if (entry.value > 1) entry.key,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('멤버 디렉토리'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: '새 멤버 등록',
              onPressed: () => _showMemberEditor(context, ref, null),
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
          if (isAdmin)
            IconButton(
              tooltip: '출결 정리 시트',
              onPressed: () => context.push('/members/report'),
              icon: const Icon(Icons.table_chart_outlined),
            ),
          if (isAdmin)
            PopupMenuButton<bool>(
              tooltip: '출결표 내보내기',
              enabled: !_exporting,
              icon: _exporting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
              onSelected: _exportAttendance,
              itemBuilder: (_) => const [
                PopupMenuItem(value: false, child: Text('전체 출결표')),
                PopupMenuItem(value: true, child: Text('신입생 출결표')),
              ],
            ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          TextField(
            onChanged: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: '이름, 학번, 포지션 검색',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.sort_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<_MemberSort>(
                  initialValue: _sort,
                  decoration: const InputDecoration(labelText: '정렬'),
                  items: const [
                    DropdownMenuItem(
                      value: _MemberSort.name,
                      child: Text('가나다순'),
                    ),
                    DropdownMenuItem(
                      value: _MemberSort.studentYear,
                      child: Text('학번순'),
                    ),
                    DropdownMenuItem(
                      value: _MemberSort.joinedYear,
                      child: Text('가입 연도순'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _sort = value ?? _sort),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('군대'),
                selected: _showMilitary,
                onSelected: (value) => setState(() => _showMilitary = value),
              ),
              FilterChip(
                label: const Text('신입생'),
                selected: _freshmenOnly,
                onSelected: (value) => setState(() => _freshmenOnly = value),
              ),
              if (isAdmin)
                FilterChip(
                  label: const Text('예약'),
                  selected: _reservationOnly,
                  onSelected: (value) =>
                      setState(() => _reservationOnly = value),
                ),
              if (isAdmin)
                FilterChip(
                  label: const Text('비활성'),
                  selected: _showInactive,
                  onSelected: (value) => setState(() => _showInactive = value),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (list.isEmpty)
            const _EmptyState(
              icon: Icons.group_off_outlined,
              title: '조건에 맞는 멤버가 없습니다',
            )
          else
            ...list.map(
              (member) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemberTile(
                  member: member,
                  showStudentId: duplicateNames.contains(member.name),
                  onTap: () {
                    final memberId = member.id;
                    if (memberId == null) return;
                    context.push('/members/${Uri.encodeComponent(memberId)}');
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _compareMembers(MemberProfile a, MemberProfile b) {
    int byName() => a.name.compareTo(b.name);
    switch (_sort) {
      case _MemberSort.name:
        return byName();
      case _MemberSort.studentYear:
        final left = _studentYearOf(a);
        final right = _studentYearOf(b);
        final result = left.compareTo(right);
        return result != 0 ? result : byName();
      case _MemberSort.joinedYear:
        final result = (a.joinedYear ?? 9999).compareTo(b.joinedYear ?? 9999);
        return result != 0 ? result : byName();
    }
  }

  int _studentYearOf(MemberProfile member) =>
      int.tryParse(member.studentId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 999;

  Future<void> _search(String value) async {
    query = value.trim();
    final revision = ++_searchRevision;
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted || revision != _searchRevision) return;
    await ref.read(lockerControllerProvider.notifier).searchMembers(query);
  }

  Future<void> _exportAttendance(bool freshmenOnly) async {
    setState(() => _exporting = true);
    try {
      final now = DateTime.now();
      final rows = await ref
          .read(lockerControllerProvider.notifier)
          .loadAttendanceReport(
            from: previousSemesterStart(now),
            to: now,
            freshmenOnly: freshmenOnly,
          );
      final saved = await AttendanceReportService().export(
        rows: rows,
        freshmenOnly: freshmenOnly,
        year: now.year,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(saved ? '출결 관리표를 저장했습니다.' : '파일 저장을 취소했습니다.')),
        );
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA attendance export failed: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('출결표를 만들지 못했습니다. 파일 형식과 저장 권한을 확인해 주세요.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

enum _MemberSort { name, studentYear, joinedYear }

/// 직전 학기의 시작일. 3~8월(1학기+여름방학)이면 지난해 9월 1일, 9~12월은
/// 올해 3월 1일, 1~2월(겨울방학)은 작년 3월 1일. 방학은 앞 학기에 포함된다.
DateTime previousSemesterStart(DateTime now) {
  if (now.month >= 3 && now.month <= 8) return DateTime(now.year - 1, 9, 1);
  if (now.month >= 9) return DateTime(now.year, 3, 1);
  return DateTime(now.year - 1, 3, 1);
}
