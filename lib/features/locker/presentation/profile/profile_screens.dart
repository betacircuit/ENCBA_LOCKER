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
      ],
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('오류 내용을 입력해 주세요.')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('오류 제보를 전송했습니다.')));
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
    ScaffoldMessenger.of(context).showSnackBar(
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
