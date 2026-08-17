part of '../locker_shell.dart';

class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segments = ref.watch(
      lockerControllerProvider.select(
        (state) => (state.gameSegment, state.gameSubSegment),
      ),
    );
    final eventsState = ref.watch(
      lockerControllerProvider.select((state) => state.eventsState),
    );
    final gameUser = ref.watch(authControllerProvider).user!;
    final isAdmin = gameUser.canAdminister;
    final selected = segments.$1;
    final selectedSub = segments.$2;
    final categories = switch (selected) {
      0 => const [
        ('아농', EventKind.morning),
        ('자개', EventKind.freeOpen),
        ('픽업게임', EventKind.pickup),
      ],
      1 => const [('1부', EventKind.ibDivision1), ('2부', EventKind.ibDivision2)],
      _ => const [
        ('연습 경기', EventKind.scrimmage),
        ('삼파전', EventKind.threeWay),
        ('외부 경기', EventKind.external),
      ],
    };
    final filtered = eventsState.events.where((event) {
      return event.kind == categories[selectedSub].$2 &&
          !event.end.isBefore(DateTime.now());
    }).toList();
    return _Page(
      header: const _Header(eyebrow: 'GAME DAY', title: 'GAME'),
      children: [
        _SlidingTabBar(
          labels: const ['내부', 'IB', '외부'],
          selectedIndex: selected,
          onSelected: ref
              .read(lockerControllerProvider.notifier)
              .selectGameSegment,
        ),
        const SizedBox(height: 12),
        _SlidingTabBar(
          labels: categories.map((category) => category.$1).toList(),
          selectedIndex: selectedSub,
          onSelected: ref
              .read(lockerControllerProvider.notifier)
              .selectGameSubSegment,
        ),
        const SizedBox(height: 20),
        if (filtered.isEmpty)
          _EmptyState(
            icon: Icons.sports_basketball_outlined,
            title: '예정된 경기가 없습니다',
            action: isAdmin ? '경기 추가' : null,
            onTap: isAdmin ? () => _openEditor(context) : null,
          )
        else
          ...filtered.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: EventTicket(
                event: event,
                heroTag: 'games-${event.id}',
                onTap: () =>
                    openEventDetail(context, event.id, heroTagPrefix: 'games'),
              ),
            ),
          ),
      ],
    );
  }
}

class _SlidingTabBar extends StatelessWidget {
  const _SlidingTabBar({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.icons,
  });

  final List<String> labels;
  final List<IconData>? icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Container(
      height: 52,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE7ECF3),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFD2DAE5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: labels.asMap().entries.map((entry) {
          final selected = entry.key == selectedIndex;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: entry.key == labels.length - 1 ? 0 : 3,
              ),
              child: Semantics(
                selected: selected,
                button: true,
                label: entry.value,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelected(entry.key),
                    child: AnimatedContainer(
                      duration: motion,
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: selected ? EncbaColors.deepBlue : Colors.white,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: selected
                            ? const [
                                BoxShadow(
                                  color: Color(0x260B2347),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icons != null) ...[
                                Icon(
                                  icons![entry.key],
                                  size: 17,
                                  color: selected
                                      ? Colors.white
                                      : EncbaColors.ink,
                                ),
                                const SizedBox(width: 5),
                              ],
                              AnimatedDefaultTextStyle(
                                duration: motion,
                                style: TextStyle(
                                  fontFamily: encbaFontFor(entry.value),
                                  fontFamilyFallback: encbaFontFallback,
                                  fontSize: 14,
                                  color: selected
                                      ? Colors.white
                                      : EncbaColors.ink,
                                ),
                                child: Text(entry.value, maxLines: 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
