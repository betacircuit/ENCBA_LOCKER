part of '../locker_shell.dart';

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
              avatarUrl: member.avatarUrl,
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
                          .map((title) => _TitleBadge(title))
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
