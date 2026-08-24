import 'package:encba_locker/core/platform/app_environment.dart';
import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PwaInstallPlatform { ios, android, desktop }

/// iOS Safari·Android Chrome·데스크톱 Chrome/Edge 등 "브라우저에서 그냥
/// 열린" 상태에서만 보이는 홈 화면 추가·설치 안내. 설치(standalone)
/// 상태가 아니면 웹에서는 항상 뜬다(다시 보지 않기 없음).
///
/// 로그인 전 화면(sign-in)과 로그인 후 프로필 탭 양쪽에서 재사용한다.
class PwaInstallCard extends ConsumerStatefulWidget {
  const PwaInstallCard({super.key});

  @override
  ConsumerState<PwaInstallCard> createState() => _PwaInstallCardState();
}

class _PwaInstallCardState extends ConsumerState<PwaInstallCard> {
  // 위에서 알림처럼 슬라이드 + 페이드로 들어오는 진입 애니메이션의 상태.
  // 처음 그려질 때는 false로 시작해, 그 다음 프레임에 true로 바뀌면서
  // AnimatedSlide/AnimatedOpacity가 목표 값까지 애니메이션한다.
  bool _entered = false;

  void _startEntranceAnimation() {
    if (_entered) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final env = const AppEnvironmentImpl();
    // 네이티브 앱·설치된 PWA에는 보이지 않는다. 그 외 웹에서는 항상 보인다.
    final installable =
        env.isAppleMobileWeb || env.isAndroidMobileWeb || env.isChromiumDesktopWeb;
    if (!installable || env.isStandalone) {
      return const SizedBox.shrink();
    }
    final platform = env.isAppleMobileWeb
        ? PwaInstallPlatform.ios
        : env.isAndroidMobileWeb
        ? PwaInstallPlatform.android
        : PwaInstallPlatform.desktop;
    final isDesktop = platform == PwaInstallPlatform.desktop;
    _startEntranceAnimation();
    final card = Card(
      color: EncbaColors.navy,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isDesktop ? null : () => _showSteps(context, platform),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Image.asset('assets/images/app_icon.png'),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'LOCKER를 홈 화면에 추가',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!isDesktop)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white70,
                ),
            ],
          ),
        ),
      ),
    );
    // 위쪽에서 알림이 뜨듯 살짝 슬라이드다운 + 페이드인.
    return AnimatedSlide(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      offset: _entered ? Offset.zero : const Offset(0, -0.35),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        opacity: _entered ? 1 : 0,
        child: card,
      ),
    );
  }

  void _showSteps(BuildContext context, PwaInstallPlatform platform) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .94,
        child: PwaInstallTutorial(
          initialPlatform: platform,
          onClose: () => Navigator.pop(sheetContext),
        ),
      ),
    );
  }
}

class PwaInstallTutorial extends StatefulWidget {
  const PwaInstallTutorial({
    required this.initialPlatform,
    required this.onClose,
    super.key,
  });

  final PwaInstallPlatform initialPlatform;
  final VoidCallback onClose;

  @override
  State<PwaInstallTutorial> createState() => _PwaInstallTutorialState();
}

class _PwaInstallTutorialState extends State<PwaInstallTutorial> {
  late PwaInstallPlatform _platform;

  @override
  void initState() {
    super.initState();
    _platform = widget.initialPlatform == PwaInstallPlatform.desktop
        ? PwaInstallPlatform.ios
        : widget.initialPlatform;
  }

  @override
  Widget build(BuildContext context) {
    final isIos = _platform == PwaInstallPlatform.ios;
    final steps = isIos ? _iosInstallSteps : _androidInstallSteps;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HOME SCREEN PLAYBOOK',
                      style: TextStyle(
                        color: EncbaColors.snuBlue,
                        fontFamily: 'BlackHanSans',
                        fontSize: 12,
                        letterSpacing: .7,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'LOCKER 홈 화면 추가 가이드',
                      style: TextStyle(
                        color: EncbaColors.navy,
                        fontFamily: 'Jua',
                        fontSize: 27,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<PwaInstallPlatform>(
            segments: const [
              ButtonSegment(
                value: PwaInstallPlatform.ios,
                icon: Icon(Icons.phone_iphone_rounded),
                label: Text('iPhone · iPad'),
              ),
              ButtonSegment(
                value: PwaInstallPlatform.android,
                icon: Icon(Icons.android_rounded),
                label: Text('Android'),
              ),
            ],
            selected: {_platform},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _platform = value.single),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            key: ValueKey(_platform),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            itemCount: steps.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              if (index == steps.length) {
                return _InstallFinishCard(isIos: isIos);
              }
              final step = steps[index];
              return _InstallStepCard(
                number: index + 1,
                title: step.title,
                description: step.description,
                tip: step.tip,
                illustration: _InstallIllustration(
                  platform: _platform,
                  step: index,
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: EncbaColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onClose,
                icon: const Icon(Icons.check_rounded),
                label: const Text('추가 방법 확인 완료'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InstallStep {
  const _InstallStep(this.title, this.description, this.tip);

  final String title;
  final String description;
  final String tip;
}

const _iosInstallSteps = [
  _InstallStep(
    'Safari에서 LOCKER 열기',
    '지금 이 페이지를 Safari로 열어 주세요. 화면 아래쪽(아이패드는 위쪽) 도구 막대에서 사각형에 위쪽 화살표가 그려진 공유 버튼을 누릅니다.',
    '카카오톡·인스타그램 등 앱 안에서 열린 브라우저에서는 이 기능을 쓸 수 없어요. 꼭 Safari로 열어야 합니다.',
  ),
  _InstallStep(
    '홈 화면에 추가 선택',
    '공유 메뉴가 뜨면 아이콘 목록을 아래로 스크롤해서 “홈 화면에 추가” 항목을 찾아 누릅니다.',
    '항목이 바로 안 보이면 계속 아래로 내려 보세요. 목록 중간쯤에 있습니다.',
  ),
  _InstallStep(
    '이름 확인 후 추가',
    '아이콘 아래 표시될 이름이 LOCKER인지 확인하고, 화면 오른쪽 위의 “추가”를 누르면 끝입니다.',
    '이름을 바꾸면 다른 부원 화면과 다르게 보일 수 있어요. 그대로 두는 걸 추천합니다.',
  ),
];

const _androidInstallSteps = [
  _InstallStep(
    'Chrome에서 LOCKER 열기',
    '지금 이 페이지를 Chrome으로 열고, 화면 오른쪽 위 점 세 개(⋮) 메뉴 버튼을 누릅니다.',
    '삼성 인터넷은 화면 아래쪽 메뉴 버튼에서 같은 항목을 찾을 수 있습니다.',
  ),
  _InstallStep(
    '홈 화면에 추가 선택',
    '메뉴 목록에서 “앱 설치” 또는 “홈 화면에 추가”를 누릅니다. 브라우저 버전에 따라 문구가 다를 수 있어요.',
    '둘 중 하나만 보여도 정상입니다. 같은 기능이니 보이는 걸 누르면 됩니다.',
  ),
  _InstallStep(
    '추가 확인',
    'LOCKER 아이콘과 이름을 확인한 뒤 뜨는 대화상자에서 “설치” 또는 “추가”를 누릅니다.',
    '추가가 끝날 때까지 Chrome을 닫지 마세요. 완료되면 홈 화면에 바로 아이콘이 생깁니다.',
  ),
];

class _InstallStepCard extends StatelessWidget {
  const _InstallStepCard({
    required this.number,
    required this.title,
    required this.description,
    required this.tip,
    required this.illustration,
  });

  final int number;
  final String title;
  final String description;
  final String tip;
  final Widget illustration;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: EncbaColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        illustration,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: EncbaColors.navy,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'BlackHanSans',
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: EncbaColors.navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(description, style: const TextStyle(height: 1.55)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: EncbaColors.highlight,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  'TIP  $tip',
                  style: const TextStyle(
                    color: EncbaColors.deepBlue,
                    fontSize: 12,
                    height: 1.4,
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

class _InstallFinishCard extends StatelessWidget {
  const _InstallFinishCard({required this.isIos});

  final bool isIos;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: EncbaColors.navy,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Container(
          width: 62,
          height: 62,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Image.asset('assets/images/app_icon.png'),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '홈 화면 추가 완료',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isIos
                    ? '홈 화면의 LOCKER 아이콘을 누르면 Safari 도구 막대 없이 열립니다.'
                    : '홈 화면의 LOCKER 아이콘을 누르면 Chrome 탭 없이 앱처럼 열립니다.',
                style: const TextStyle(
                  color: Color(0xFFD4E1F0),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InstallIllustration extends StatelessWidget {
  const _InstallIllustration({required this.platform, required this.step});

  final PwaInstallPlatform platform;
  final int step;

  @override
  Widget build(BuildContext context) => Container(
    height: 232,
    color: const Color(0xFFE8EEF6),
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: _PhonePreview(
          child: platform == PwaInstallPlatform.ios
              ? _IosInstallPreview(step: step)
              : _AndroidInstallPreview(step: step),
        ),
      ),
    ),
  );
}

class _PhonePreview extends StatelessWidget {
  const _PhonePreview({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: EncbaColors.ink,
      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
    ),
    padding: const EdgeInsets.fromLTRB(7, 9, 7, 0),
    child: ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
      child: ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            const SizedBox(
              height: 22,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Text('9:41', style: TextStyle(fontSize: 9)),
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: 11),
                    child: Icon(Icons.wifi_rounded, size: 12),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

class _IosInstallPreview extends StatelessWidget {
  const _IosInstallPreview({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) => switch (step) {
    0 => const _BrowserPreview(
      topBar: false,
      action: _TargetAction(icon: Icons.ios_share_rounded, label: '공유'),
    ),
    1 => const _MenuPreview(
      title: '공유',
      targetIcon: Icons.add_box_outlined,
      targetLabel: '홈 화면에 추가',
      rows: ['복사', '읽기 목록에 추가', '북마크 추가'],
    ),
    _ => const _ConfirmPreview(
      buttonLabel: '추가',
      subtitle: 'encba-locker.vercel.app',
    ),
  };
}

class _AndroidInstallPreview extends StatelessWidget {
  const _AndroidInstallPreview({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) => switch (step) {
    0 => const _BrowserPreview(
      topBar: true,
      action: _TargetAction(icon: Icons.more_vert_rounded, label: '메뉴'),
    ),
    1 => const _MenuPreview(
      title: 'Chrome 메뉴',
      targetIcon: Icons.install_mobile_rounded,
      targetLabel: '앱 설치',
      rows: ['새 탭', '방문 기록', '다운로드'],
    ),
    _ => const _ConfirmPreview(
      buttonLabel: '설치',
      subtitle: '홈 화면에 LOCKER를 추가합니다',
    ),
  };
}

class _TargetAction {
  const _TargetAction({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _BrowserPreview extends StatelessWidget {
  const _BrowserPreview({required this.topBar, required this.action});

  final bool topBar;
  final _TargetAction action;

  @override
  Widget build(BuildContext context) {
    final toolbar = Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        border: Border.symmetric(horizontal: BorderSide(color: EncbaColors.line)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'encba-locker.vercel.app',
              style: TextStyle(fontSize: 9, color: EncbaColors.muted),
            ),
          ),
          _TapTarget(icon: action.icon, label: action.label),
        ],
      ),
    );
    return Column(
      children: [
        if (topBar) toolbar,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LOCKER',
                  style: TextStyle(
                    fontFamily: 'BlackHanSans',
                    fontSize: 20,
                    color: EncbaColors.navy,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: EncbaColors.highlight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var index = 0; index < 3; index++) ...[
                      Expanded(
                        child: Container(
                          height: 34,
                          decoration: BoxDecoration(
                            color: index == 1
                                ? EncbaColors.timeMarker
                                : const Color(0xFFF0F2F5),
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                      if (index < 2) const SizedBox(width: 7),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!topBar) toolbar,
      ],
    );
  }
}

class _TapTarget extends StatelessWidget {
  const _TapTarget({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3D9),
          shape: BoxShape.circle,
          border: Border.all(color: EncbaColors.late, width: 2),
        ),
        child: Icon(icon, size: 16, color: EncbaColors.deepBlue),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          color: EncbaColors.late,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _MenuPreview extends StatelessWidget {
  const _MenuPreview({
    required this.title,
    required this.targetIcon,
    required this.targetLabel,
    required this.rows,
  });

  final String title;
  final IconData targetIcon;
  final String targetLabel;
  final List<String> rows;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF1F3F6),
    padding: const EdgeInsets.fromLTRB(13, 10, 13, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: EncbaColors.muted)),
        const SizedBox(height: 7),
        for (final row in rows)
          _MenuRow(icon: Icons.circle_outlined, label: row),
        Container(
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3D9),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: EncbaColors.late, width: 2),
          ),
          child: _MenuRow(icon: targetIcon, label: targetLabel, emphasized: true),
        ),
      ],
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 31,
    child: Row(
      children: [
        Icon(icon, size: 14, color: EncbaColors.deepBlue),
        const SizedBox(width: 9),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: EncbaColors.ink,
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w400,
          ),
        ),
      ],
    ),
  );
}

class _ConfirmPreview extends StatelessWidget {
  const _ConfirmPreview({required this.buttonLabel, required this.subtitle});

  final String buttonLabel;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(15),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('취소', style: TextStyle(fontSize: 10)),
            const Text(
              '홈 화면에 추가',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3D9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EncbaColors.late, width: 2),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  color: EncbaColors.deepBlue,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Container(
              width: 54,
              height: 54,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: EncbaColors.navy,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Image.asset('assets/images/app_icon.png'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LOCKER',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 9, color: EncbaColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
