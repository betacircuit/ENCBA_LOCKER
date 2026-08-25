part of '../locker_shell.dart';

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.onTap,
    this.showStudentId = false,
  });
  final MemberProfile member;
  final VoidCallback onTap;

  /// 동명이인이 있을 때 true. 제목 옆에 학번 배지를 붙여 누구인지 구분한다.
  final bool showStudentId;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leading: _Avatar(
        name: member.name,
        size: 48,
        avatarUrl: member.avatarUrl,
        isActive: member.isActiveMember,
      ),
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
          if (showStudentId && member.studentId != '학번 미등록') ...[
            const SizedBox(width: 6),
            _SmallBadge(member.studentId),
          ],
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
    this.avatarUrl,
    this.isActive,
  });
  final String name;
  final double size;
  final String? photoBase64;

  /// 다른 부원의 공개 프로필 사진 주소. photoBase64(내 사진)보다 우선하지
  /// 않고, 둘 다 없으면 이니셜로 표시한다.
  final String? avatarUrl;

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
    child: photoBase64 != null
        ? Image.memory(
            base64Decode(photoBase64!),
            width: size,
            height: size,
            fit: BoxFit.cover,
          )
        : avatarUrl != null
        ? Image.network(
            avatarUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _initials(),
          )
        : _initials(),
  );

  Widget _initials() => Text(
    name.substring(0, 1),
    style: TextStyle(
      fontFamily: 'Jua',
      fontSize: size * .34,
      color: EncbaColors.deepBlue,
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
