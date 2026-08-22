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
  const MemberDirectoryScreen({super.key});

  @override
  ConsumerState<MemberDirectoryScreen> createState() =>
      _MemberDirectoryScreenState();
}

class _MemberDirectoryScreenState extends ConsumerState<MemberDirectoryScreen> {
  String query = '';
  int _searchRevision = 0;
  _MemberSort _sort = _MemberSort.studentYear;
  bool _showMilitary = false;
  bool _showInactive = false;
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
      // 평소처럼 군휴학·비활성 인원을 목록에서 뺀다.
      final isMilitary = member.status == 'MILITARY_LEAVE';
      if (_showMilitary != isMilitary) return false;
      if (_showInactive == member.isActive) return false;
      if (_reservationOnly && !member.isReservationManager) return false;
      if (_freshmenOnly && !member.isFreshman) return false;
      return true;
    }).toList()..sort(_compareMembers);
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
                      value: _MemberSort.studentYear,
                      child: Text('학번순'),
                    ),
                    DropdownMenuItem(
                      value: _MemberSort.name,
                      child: Text('가나다순'),
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
            from: DateTime(now.year),
            to: DateTime(now.year + 1),
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

enum _MemberSort { studentYear, name, joinedYear }

class AttendanceReportScreen extends ConsumerStatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  ConsumerState<AttendanceReportScreen> createState() =>
      _AttendanceReportScreenState();
}

class _AttendanceReportScreenState
    extends ConsumerState<AttendanceReportScreen> {
  bool _freshmenOnly = false;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  List<AttendanceReportRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final now = DateTime.now();
      final rows = await ref
          .read(lockerControllerProvider.notifier)
          .loadAttendanceReport(
            from: DateTime(now.year),
            to: DateTime(now.year + 1),
            freshmenOnly: _freshmenOnly,
          );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA attendance sheet load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '출결 정보를 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _export() async {
    if (_exporting || _rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final saved = await AttendanceReportService().export(
        rows: _rows,
        freshmenOnly: _freshmenOnly,
        year: DateTime.now().year,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(saved ? '출결 관리표를 저장했습니다.' : '파일 저장을 취소했습니다.')),
        );
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA attendance sheet export failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('출결 관리표를 저장하지 못했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdminister =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    final summaries = _summaries(_rows);
    final eventCount = _rows.map((row) => row.eventId).toSet().length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('출결 정리 시트'),
        actions: [
          if (canAdminister)
            IconButton(
              tooltip: '엑셀로 저장',
              onPressed: _exporting || _rows.isEmpty ? null : _export,
              icon: _exporting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
            ),
        ],
      ),
      body: !canAdminister
          ? const Center(child: Text('관리자만 확인할 수 있습니다.'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('전체')),
                          ButtonSegment(value: true, label: Text('신입생')),
                        ],
                        selected: {_freshmenOnly},
                        onSelectionChanged: (selection) {
                          final next = selection.first;
                          if (next == _freshmenOnly) return;
                          setState(() => _freshmenOnly = next);
                          _load();
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${DateTime.now().year}년 · 일정 $eventCount개 · 인원 ${summaries.length}명',
                        style: const TextStyle(color: EncbaColors.muted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: switch ((_loading, _error, summaries.isEmpty)) {
                    (true, _, _) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    (false, final error?, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _load,
                            child: const Text('다시 불러오기'),
                          ),
                        ],
                      ),
                    ),
                    (false, null, true) => const Center(
                      child: Text('정리할 출결 정보가 없습니다.'),
                    ),
                    _ => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 22,
                          columns: const [
                            DataColumn(label: Text('학번')),
                            DataColumn(label: Text('이름')),
                            DataColumn(label: Text('참석'), numeric: true),
                            DataColumn(label: Text('불참'), numeric: true),
                            DataColumn(label: Text('미정/미응답'), numeric: true),
                            DataColumn(label: Text('참석률'), numeric: true),
                          ],
                          rows: summaries
                              .map(
                                (item) => DataRow(
                                  cells: [
                                    DataCell(
                                      Text(item.studentYear?.toString() ?? '-'),
                                    ),
                                    DataCell(Text(item.name)),
                                    DataCell(Text('${item.attending}')),
                                    DataCell(Text('${item.absent}')),
                                    DataCell(Text('${item.undecided}')),
                                    DataCell(Text('${item.rate}%')),
                                  ],
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ),
                  },
                ),
              ],
            ),
    );
  }

  List<_AttendanceSummary> _summaries(List<AttendanceReportRow> rows) {
    final byMember = <String, List<AttendanceReportRow>>{};
    for (final row in rows) {
      byMember.putIfAbsent(row.directoryId, () => []).add(row);
    }
    final result =
        byMember.values
            .map((memberRows) {
              final first = memberRows.first;
              final attending = memberRows
                  .where((row) => row.choice == '참석')
                  .length;
              final absent = memberRows
                  .where((row) => row.choice == '불참')
                  .length;
              final undecided = memberRows.length - attending - absent;
              return _AttendanceSummary(
                name: first.memberName,
                studentYear: first.studentYear,
                attending: attending,
                absent: absent,
                undecided: undecided,
                rate: memberRows.isEmpty
                    ? 0
                    : ((attending / memberRows.length) * 100).round(),
              );
            })
            .toList(growable: false)
          ..sort((a, b) {
            final byYear = (a.studentYear ?? 999).compareTo(
              b.studentYear ?? 999,
            );
            return byYear != 0 ? byYear : a.name.compareTo(b.name);
          });
    return result;
  }
}

class _AttendanceSummary {
  const _AttendanceSummary({
    required this.name,
    required this.studentYear,
    required this.attending,
    required this.absent,
    required this.undecided,
    required this.rate,
  });

  final String name;
  final int? studentYear;
  final int attending;
  final int absent;
  final int undecided;
  final int rate;
}

class _DetailLoadScaffold extends StatelessWidget {
  const _DetailLoadScaffold({
    required this.title,
    required this.loading,
    required this.notFound,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final bool loading;
  final bool notFound;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    notFound
                        ? Icons.search_off_rounded
                        : Icons.cloud_off_outlined,
                    size: 42,
                    color: EncbaColors.muted,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    notFound
                        ? '$title 정보를 찾지 못했습니다.'
                        : '$title 정보를 불러오지 못했습니다.',
                    textAlign: TextAlign.center,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 6),
                    const Text(
                      '연결 상태를 확인한 뒤 다시 시도해 주세요.',
                      style: TextStyle(color: EncbaColors.muted),
                    ),
                  ],
                  if (!notFound) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ],
              ),
      ),
    ),
  );
}

class MemberDetailScreen extends ConsumerStatefulWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  final String memberId;

  @override
  ConsumerState<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  bool _loading = true;
  bool _notFound = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final found = await ref
          .read(lockerControllerProvider.notifier)
          .ensureMember(widget.memberId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = !found;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = ref
        .watch(
          lockerControllerProvider.select(
            (state) => state.membersState.members,
          ),
        )
        .where((item) => item.id == widget.memberId)
        .firstOrNull;
    if (member != null) return _MemberDetailView(member: member);
    return _DetailLoadScaffold(
      title: '멤버 정보',
      loading: _loading,
      notFound: _notFound,
      error: _error,
      onRetry: _retry,
    );
  }

  void _retry() {
    setState(() {
      _loading = true;
      _notFound = false;
      _error = null;
    });
    _load();
  }
}

class _MemberDetailView extends ConsumerWidget {
  const _MemberDetailView({required this.member});

  final MemberProfile member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('멤버 정보')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: _Avatar(
              name: member.name,
              size: 88,
              isActive: member.isActive,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            member.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 5),
          Text(
            '${member.studentId} · ${member.joinedYear == null ? '가입 연도 미등록' : '${member.joinedYear} 가입'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: EncbaColors.muted),
          ),
          const SizedBox(height: 22),
          Card(
            child: Column(
              children: [
                if (member.leadershipLabel != null)
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('직책'),
                    trailing: _LeadershipBadge(member.leadershipRole),
                  ),
                if (member.titles.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.local_offer_outlined),
                    title: const Text('담당'),
                    trailing: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: member.titles
                          .map((title) => _SmallBadge(title))
                          .toList(),
                    ),
                  ),
                if (member.department.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: const Text('학과'),
                    trailing: Text(member.department),
                  ),
                ListTile(
                  leading: const Icon(Icons.sports_basketball_outlined),
                  title: const Text('포지션 · 등번호'),
                  trailing: Text(
                    member.jerseyNumber == 0
                        ? member.position
                        : '${member.position} · #${member.jerseyNumber}',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: const Text('전화번호'),
                  trailing: Text(
                    member.phone.trim().isEmpty ? '미등록' : member.phone,
                    style: TextStyle(
                      color: member.phone.trim().isEmpty
                          ? EncbaColors.muted
                          : EncbaColors.snuBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: member.phone.trim().isEmpty
                      ? null
                      : () =>
                            _launch(context, 'tel:${_dialableNumber(member.phone)}'),
                ),
                if (member.isReservationManager)
                  const ListTile(
                    leading: Icon(Icons.event_available_outlined),
                    title: Text('체육관 예약자'),
                    trailing: _SmallBadge('예약자'),
                  ),
                if (member.isFreshman)
                  const ListTile(
                    leading: Icon(Icons.new_releases_outlined),
                    title: Text('멤버 특성'),
                    trailing: _SmallBadge('신입생'),
                  ),
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('소속'),
                  trailing: Text(member.teamLabel),
                ),
                ListTile(
                  leading: Icon(switch (member.status) {
                    'MILITARY_LEAVE' => Icons.military_tech_outlined,
                    'EXCHANGE_STUDENT' ||
                    'STUDY_ABROAD' => Icons.flight_takeoff_outlined,
                    _ => Icons.school_outlined,
                  }),
                  title: const Text('상태'),
                  trailing: Text(_statusLabel(member.status)),
                ),
                if (isAdmin && member.id != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.edit_note_rounded),
                    title: const Text('정보 및 직책 수정'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showMemberEditor(context, ref, member),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    value: member.isActive,
                    secondary: const Icon(Icons.manage_accounts_outlined),
                    title: const Text('계정 활성화'),
                    subtitle: Text(member.isActive ? '로그인 가능' : '로그인 차단'),
                    onChanged: (value) async {
                      final saved = await ref
                          .read(lockerControllerProvider.notifier)
                          .setMemberActive(member, value);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                saved ? '계정 상태를 변경했습니다.' : '변경하지 못했습니다.',
                              ),
                            ),
                          );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 전화 앱에 넘길 때는 구분 기호를 떼어 낸다.
String _dialableNumber(String phone) =>
    phone.replaceAll(RegExp(r'[^0-9+]'), '');

/// [member]가 null이면 구글 로그인 대조용 가입 명단에 아직 없는 사람을
/// 새로 등록하는 화면이 된다.
Future<void> _showMemberEditor(
  BuildContext context,
  WidgetRef ref,
  MemberProfile? member,
) async {
  final isNew = member == null;
  final base =
      member ??
      const MemberProfile(
        name: '',
        studentId: '',
        generation: 1,
        status: 'YB',
        position: '미정',
        teams: ['ENCBA'],
        note: '',
      );
  final name = TextEditingController(text: base.name);
  final studentYear = TextEditingController(
    text: base.studentId.replaceAll(RegExp(r'[^0-9]'), ''),
  );
  final joinedYear = TextEditingController(
    text: base.joinedYear?.toString() ?? '',
  );
  final phone = TextEditingController(text: base.phone);
  final department = TextEditingController(text: base.department);
  final jersey = TextEditingController(text: base.jerseyNumber.toString());
  final newTitle = TextEditingController();
  var position = base.position;
  var status = base.status;
  var role = base.leadershipRole;
  var isReservationManager = base.isReservationManager;
  var isFreshman = base.isFreshman;
  var isActive = base.isActive;
  var teams = {...base.teams};
  var titles = List<String>.of(base.titles);
  String? validationError;

  final save = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isNew ? '새 멤버 등록' : '멤버 정보 수정',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (isNew) ...[
                  const SizedBox(height: 4),
                  const Text(
                    '구글 로그인 때 대조하는 가입 명단에 실명을 추가합니다. '
                    '이후 본인이 같은 실명으로 학교 Google 계정을 인증하면 가입이 이어집니다.',
                    style: TextStyle(color: EncbaColors.muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '실명'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: studentYear,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '학번'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: joinedYear,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '엔크바 가입 년도',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '전화번호'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: department,
                  decoration: const InputDecoration(labelText: '학과'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: position,
                        decoration: const InputDecoration(labelText: '포지션'),
                        items: const ['PG', 'SG', 'SF', 'PF', 'C', '미정']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => position = value ?? position,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: jersey,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '등번호'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: '직책'),
                  items:
                      const {
                            'member': '부원',
                            'manager': '매니저',
                            'captain': '주장',
                            'admin': '관리자',
                          }.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => role = value ?? role,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '상태'),
                  items:
                      const {
                            'YB': '재학',
                            'OB': 'OB',
                            'MILITARY_LEAVE': '군 휴학',
                            'EXCHANGE_STUDENT': '교환학생',
                            'STUDY_ABROAD': '유학',
                            'GRADUATED': '졸업',
                            'INACTIVE': '비활동',
                          }.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => status = value ?? status,
                ),
                const SizedBox(height: 8),
                const Text('소속'),
                Wrap(
                  spacing: 8,
                  children: ['ENCBA', 'BEN'].map((team) {
                    return FilterChip(
                      label: Text(team),
                      selected: teams.contains(team),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          teams.add(team);
                        } else if (teams.length > 1) {
                          teams.remove(team);
                        }
                      }),
                    );
                  }).toList(),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  title: const Text('계정 활성화'),
                  onChanged: (value) => setState(() => isActive = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: isReservationManager,
                  title: const Text('체육관 예약자'),
                  subtitle: const Text('화요일 09:30 예약 오픈 알림 대상'),
                  onChanged: (value) =>
                      setState(() => isReservationManager = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: isFreshman,
                  title: const Text('신입생'),
                  onChanged: (value) => setState(() => isFreshman = value),
                ),
                const SizedBox(height: 8),
                const Text('직책(표시용, 여러 개 가능)'),
                const SizedBox(height: 6),
                if (titles.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: titles
                        .map(
                          (title) => InputChip(
                            label: Text(title),
                            onDeleted: () =>
                                setState(() => titles.remove(title)),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newTitle,
                        decoration: const InputDecoration(
                          labelText: '직책 추가',
                          hintText: '예: 벤 감독',
                        ),
                        onSubmitted: (_) => setState(() {
                          final value = newTitle.text.trim();
                          if (value.isEmpty || titles.contains(value)) return;
                          titles.add(value);
                          newTitle.clear();
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '추가',
                      onPressed: () => setState(() {
                        final value = newTitle.text.trim();
                        if (value.isEmpty || titles.contains(value)) return;
                        titles.add(value);
                        newTitle.clear();
                      }),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final joined = int.tryParse(joinedYear.text.trim());
                    final number = int.tryParse(jersey.text.trim());
                    if (name.text.trim().isEmpty ||
                        (joined != null && (joined < 1977 || joined > 2100)) ||
                        number == null ||
                        number < 0 ||
                        number > 99) {
                      setState(
                        () => validationError =
                            '이름과 등번호를 확인해 주세요. 가입 연도는 비어 있어도 됩니다.',
                      );
                      return;
                    }
                    Navigator.pop(sheetContext, true);
                  },
                  child: Text(isNew ? '멤버 등록' : '변경 사항 저장'),
                ),
                if (validationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (save == true) {
    final updated = base.copyWith(
      name: name.text.trim(),
      studentId: '${studentYear.text.trim()}학번',
      joinedYear: int.tryParse(joinedYear.text.trim()),
      phone: phone.text.trim(),
      position: position,
      jerseyNumber: int.parse(jersey.text.trim()),
      status: status,
      teams: teams.toList()..sort(),
      leadershipRole: role,
      isActive: isActive,
      isReservationManager: isReservationManager,
      department: department.text.trim(),
      isFreshman: isFreshman,
      titles: titles,
    );
    final notifier = ref.read(lockerControllerProvider.notifier);
    final failure = isNew
        ? await notifier.addMember(updated)
        : await notifier.updateMember(updated);
    if (context.mounted && failure != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isNew ? '멤버를 등록하지 못했습니다' : '멤버 정보를 저장하지 못했습니다'),
          content: Text(failure),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }
  name.dispose();
  studentYear.dispose();
  joinedYear.dispose();
  phone.dispose();
  department.dispose();
  newTitle.dispose();
  jersey.dispose();
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.onTap});
  final MemberProfile member;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leading: _Avatar(name: member.name, size: 48, isActive: member.isActive),
      title: Row(
        children: [
          Expanded(
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (member.leadershipLabel != null) ...[
            const SizedBox(width: 6),
            _LeadershipBadge(member.leadershipRole),
          ] else if (member.badge != null) ...[
            const SizedBox(width: 6),
            _SmallBadge(member.badge!),
          ],
        ],
      ),
      subtitle: Text('${member.teamLabel} · ${member.position} · ${member.studentId}'),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

/// 관리자·주장·매니저 직책을 역할별 색으로 눈에 띄게 보여주는 뱃지.
/// 카드 배경은 손대지 않고 이 뱃지만 꾸며서, 목록이 온통 색으로 뒤덮이지
/// 않으면서도 직책은 한눈에 들어오게 한다.
class _LeadershipBadge extends StatelessWidget {
  const _LeadershipBadge(this.role);
  final String role;

  @override
  Widget build(BuildContext context) {
    final style = switch (role) {
      'admin' => const _LeadershipBadgeStyle(
        colors: [Color(0xFF3A3D45), Color(0xFF0E0F12)],
        foreground: Colors.white,
        icon: Icons.shield_rounded,
        label: '관리자',
      ),
      'captain' => const _LeadershipBadgeStyle(
        colors: [Color(0xFFFCE7AE), Color(0xFFC98F26)],
        foreground: EncbaColors.navy,
        icon: Icons.emoji_events_rounded,
        label: '주장',
      ),
      'manager' => const _LeadershipBadgeStyle(
        colors: [Color(0xFFFF9BC2), Color(0xFFE0417F)],
        foreground: Colors.white,
        icon: Icons.workspace_premium_rounded,
        label: '매니저',
      ),
      _ => null,
    };
    if (style == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: style.colors),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: style.colors.last.withValues(alpha: .35),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 11, color: style.foreground),
          const SizedBox(width: 3),
          Text(
            style.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: style.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadershipBadgeStyle {
  const _LeadershipBadgeStyle({
    required this.colors,
    required this.foreground,
    required this.icon,
    required this.label,
  });
  final List<Color> colors;
  final Color foreground;
  final IconData icon;
  final String label;
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.size,
    this.photoBase64,
    this.isActive,
  });
  final String name;
  final double size;
  final String? photoBase64;

  /// null이면 표시하지 않고, 값이 있으면 인스타그램 접속 표시처럼
  /// 아바타 모서리에 초록(활성)/빨강(비활성) 점을 얹는다.
  final bool? isActive;

  @override
  Widget build(BuildContext context) {
    final circle = _circle();
    if (isActive == null) return circle;
    final dotSize = size * .3;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          circle,
          Positioned(
            right: -dotSize * .1,
            bottom: -dotSize * .1,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: isActive!
                    ? const Color(0xFF35C759)
                    : const Color(0xFFE5484D),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle() => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: EncbaColors.highlight,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFC9D9EA)),
    ),
    clipBehavior: Clip.antiAlias,
    child: photoBase64 == null
        ? Text(
            name.substring(0, 1),
            style: TextStyle(
              fontFamily: 'Jua',
              fontSize: size * .34,
              color: EncbaColors.deepBlue,
            ),
          )
        : Image.memory(
            base64Decode(photoBase64!),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
  );
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: EncbaColors.late.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: Color(0xFF995A00),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontFamily: 'BlackHanSans',
          fontSize: 22,
          color: EncbaColors.deepBlue,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: EncbaColors.muted),
      ),
    ],
  );
}

class _Rule extends StatelessWidget {
  const _Rule();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: EncbaColors.line);
}
