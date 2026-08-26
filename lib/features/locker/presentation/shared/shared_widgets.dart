part of '../locker_shell.dart';

class _Page extends StatelessWidget {
  const _Page({
    required this.header,
    required this.children,
    this.controller,
    this.scrollKey,
  });
  final Widget header;
  final List<Widget> children;
  final ScrollController? controller;
  final Key? scrollKey;
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListView(
      key: scrollKey,
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [header, const SizedBox(height: 22), ...children],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.eyebrow, required this.title, this.action});
  final String eyebrow;
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: TextStyle(
                fontFamily: encbaFontFor(eyebrow),
                color: EncbaColors.snuBlue,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontFamily: encbaFontFor(title, display: true),
              ),
            ),
          ],
        ),
      ),
      ?action,
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
    ],
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice, required this.onTap});
  final AnnouncementItem notice;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: EncbaColors.late.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.campaign_outlined, color: EncbaColors.late),
      ),
      title: Text(
        notice.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${notice.author} · ${_relativeTime(notice.publishedAt)}'),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

String _relativeTime(DateTime value) {
  final elapsed = DateTime.now().difference(value);
  if (elapsed.inMinutes < 1) return '방금 전';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
  if (elapsed.inDays < 1) return '${elapsed.inHours}시간 전';
  if (elapsed.inDays < 2) return '어제';
  if (elapsed.inDays < 7) return '${elapsed.inDays}일 전';
  return '${value.month}.${value.day}';
}

String _formatTimestamp(double seconds) {
  final total = seconds.round().clamp(0, 359999);
  final minutes = total ~/ 60;
  final remainder = total % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.action,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: EncbaColors.line),
    ),
    child: Column(
      children: [
        Icon(icon, size: 36, color: EncbaColors.muted),
        const SizedBox(height: 10),
        Text(title),
        if (action != null) ...[
          const SizedBox(height: 10),
          TextButton(onPressed: onTap, child: Text(action!)),
        ],
      ],
    ),
  );
}

void _showTask(BuildContext context, String text) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (_) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '운영 체크리스트',
            style: TextStyle(
              fontFamily: 'Jua',
              fontSize: 24,
              color: EncbaColors.navy,
            ),
          ),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    ),
  ),
);

/// 링크를 열지 못했을 때 조용히 아무 일도 없는 것처럼 끝나지 않도록,
/// 실패하면 스낵바로 알린다. (Instagram 릴스처럼 외부 앱으로 나가는 링크가
/// 팝업 차단 등으로 막히면 이전에는 탭해도 눈에 보이는 반응이 전혀 없었다.)
Future<void> _launch(BuildContext context, String raw) async {
  final uri = _isInstagramReel(raw)
      ? _normalizedInstagramUri(raw)
      : Uri.tryParse(raw);
  final opened =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('링크를 열지 못했습니다.')));
  }
}
