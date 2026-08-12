import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/services/calendar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openEventDetail(
  BuildContext context,
  LockerEvent event, {
  String heroTagPrefix = 'event',
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) =>
          EventDetailScreen(
            eventId: event.id,
            initialEvent: event,
            heroTag: '$heroTagPrefix-${event.id}',
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(curve),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
    ),
  );
}

class EventTicket extends ConsumerWidget {
  const EventTicket({
    super.key,
    required this.event,
    required this.heroTag,
    required this.onTap,
    this.compact = false,
  });

  final LockerEvent event;
  final String heroTag;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = _kindColor(event.kind);
    if (event.isLocked) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: EncbaColors.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${event.start.month}.${event.start.day} · 출전 명단 확정 후 공개',
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EncbaColors.line),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(17),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 15 : 19),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                EventKindLabel(kind: event.kind),
                                const Spacer(),
                                Text(
                                  '${event.start.month}.${event.start.day} ${weekday(event.start)}',
                                  style: const TextStyle(
                                    color: EncbaColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: compact ? 10 : 16),
                            Text(
                              event.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: encbaFontFor(
                                  event.title,
                                  display: true,
                                ),
                                fontSize: compact ? 18 : 23,
                                height: 1.15,
                                fontWeight: event.isBattle
                                    ? FontWeight.normal
                                    : FontWeight.w700,
                                color: EncbaColors.ink,
                              ),
                            ),
                            if (event.opponents.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                'vs ${event.opponents.join(' · ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: EncbaColors.snuBlue,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            _MetaLine(
                              icon: Icons.schedule_rounded,
                              text: '${time(event.start)}–${time(event.end)}',
                              emphasized: true,
                              markerColor: EncbaColors.timeMarker,
                            ),
                            const SizedBox(height: 7),
                            _MetaLine(
                              icon: Icons.location_on_outlined,
                              text: event.fullPlace,
                              emphasized: true,
                              markerColor: EncbaColors.placeMarker,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 14),
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: EncbaColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (event.responseEnabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: AttendanceSelector(event: event, compact: true),
            ),
          ],
        ],
      ),
    );
  }
}

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({
    super.key,
    required this.eventId,
    required this.initialEvent,
    required this.heroTag,
  });

  final String eventId;
  final LockerEvent initialEvent;
  final String heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(lockerControllerProvider).events;
    final event =
        events.where((item) => item.id == eventId).firstOrNull ?? initialEvent;
    final isAdmin =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    if (event.isLocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('외부 경기')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 40),
                const SizedBox(height: 14),
                Text(
                  event.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('출전 인원이 확정되면 선택된 부원에게만 상세 정보가 열립니다.'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final ok = await ref
                        .read(lockerControllerProvider.notifier)
                        .applyExternalEvent(event.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? '참여 신청을 보냈습니다.' : '신청을 저장하지 못했습니다.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('참여 신청'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('일정 상세'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: '일정 수정',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventEditorScreen(existing: event),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
        children: [
          Material(
            color: Colors.transparent,
            child: _ExpandedTicket(event: event),
          ),
          if (event.memo.trim().isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('안내', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 9),
            Text(event.memo, style: const TextStyle(height: 1.7)),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openMap(context, event),
                  icon: const Icon(Icons.near_me_outlined),
                  label: const Text('네이버 지도'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addCalendar(context, event),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('캘린더에 추가'),
                ),
              ),
            ],
          ),
          if (isAdmin && event.kind == EventKind.external) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventRosterScreen(event: event),
                ),
              ),
              icon: const Icon(Icons.how_to_reg_outlined),
              label: const Text('출전 명단 확정'),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EncbaColors.highlight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '수정 이력',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${event.createdBy} · ${event.updatedAt}\n일정 등록 및 최근 수정',
                  style: const TextStyle(
                    color: EncbaColors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EventRosterScreen extends ConsumerStatefulWidget {
  const EventRosterScreen({super.key, required this.event});

  final LockerEvent event;

  @override
  ConsumerState<EventRosterScreen> createState() => _EventRosterScreenState();
}

class _EventRosterScreenState extends ConsumerState<EventRosterScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(lockerControllerProvider.notifier)
          .loadEventRoster(widget.event.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roster =
        ref.watch(lockerControllerProvider).eventRosters[widget.event.id] ??
        const <EventRosterMember>[];
    return Scaffold(
      appBar: AppBar(title: const Text('출전 명단 확정')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.event.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text('참여 신청자를 확정하면 해당 부원에게만 경기 상세가 열립니다.'),
          const SizedBox(height: 18),
          if (roster.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('아직 참여 신청자가 없습니다.'),
              ),
            )
          else
            ...roster.map(
              (member) => Card(
                child: ListTile(
                  title: Text(member.name),
                  subtitle: Text(switch (member.status) {
                    'confirmed' => '출전 확정',
                    'declined' => '미선발',
                    _ => '참여 신청',
                  }),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'confirmed', label: Text('확정')),
                      ButtonSegment(value: 'declined', label: Text('제외')),
                    ],
                    selected: {
                      member.status == 'applied' ? 'declined' : member.status,
                    },
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => ref
                        .read(lockerControllerProvider.notifier)
                        .setEventRosterStatus(
                          eventId: widget.event.id,
                          member: member,
                          status: selection.first,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExpandedTicket extends StatelessWidget {
  const _ExpandedTicket({required this.event});
  final LockerEvent event;

  @override
  Widget build(BuildContext context) {
    final accent = _kindColor(event.kind);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: event.isBattle ? EncbaColors.navy : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: event.isBattle ? EncbaColors.navy : EncbaColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EventKindLabel(kind: event.kind, inverted: event.isBattle),
              const Spacer(),
              if (event.uniformColors.isNotEmpty)
                Text(
                  '${event.uniformColors.join(' · ')} 유니폼',
                  style: TextStyle(
                    color: event.isBattle ? Colors.white70 : EncbaColors.muted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            event.title,
            style: TextStyle(
              fontFamily: encbaFontFor(event.title, display: true),
              color: event.isBattle ? Colors.white : EncbaColors.navy,
              fontSize: 32,
              height: 1.1,
            ),
          ),
          if (event.opponents.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'vs ${event.opponents.join(' · ')}',
              style: TextStyle(
                color: event.isBattle ? Colors.white70 : EncbaColors.snuBlue,
                fontSize: 15,
              ),
            ),
          ],
          const SizedBox(height: 18),
          _MetaLine(
            icon: Icons.calendar_today_outlined,
            text:
                '${event.start.month}월 ${event.start.day}일 ${weekday(event.start)}요일',
            color: event.isBattle ? Colors.white : EncbaColors.ink,
          ),
          const SizedBox(height: 7),
          _MetaLine(
            icon: Icons.schedule_rounded,
            text: '${time(event.start)}–${time(event.end)}',
            color: EncbaColors.navy,
            emphasized: true,
            markerColor: EncbaColors.timeMarker,
          ),
          const SizedBox(height: 9),
          _MetaLine(
            icon: Icons.location_on_outlined,
            text: event.fullPlace,
            color: EncbaColors.navy,
            emphasized: true,
            markerColor: EncbaColors.placeMarker,
          ),
          const SizedBox(height: 18),
          Container(height: 2, width: 70, color: accent),
          const SizedBox(height: 12),
          Text(
            '${event.targetTeam} · ${event.attending}명 참석 예정${event.capacity == null ? '' : ' / ${event.capacity}명'}',
            style: TextStyle(
              color: event.isBattle ? Colors.white70 : EncbaColors.muted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class AttendanceSelector extends ConsumerWidget {
  const AttendanceSelector({
    super.key,
    required this.event,
    this.compact = false,
  });
  final LockerEvent event;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected =
        ref.watch(lockerControllerProvider).attendance[event.id] ?? '미정';
    final isAdmin =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    final isClosed = DateTime.now().isAfter(event.responseDeadline) && !isAdmin;
    final choices = event.pollOptions
        .map((label) => (label, _choiceIcon(label), _choiceColor(label)))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = choices.length <= 4 ? choices.length : 2;
        final width = (constraints.maxWidth - (columns - 1) * 7) / columns;
        return Wrap(
          spacing: 7,
          runSpacing: 7,
          children: choices.map((choice) {
            final active = selected == choice.$1;
            return SizedBox(
              width: width,
              child: Semantics(
                selected: active,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: isClosed
                      ? null
                      : () async {
                          String? reason;
                          if (choice.$1 == '불참') {
                            reason = await _askAbsenceReason(context);
                            if (reason == null) return;
                          }
                          final saved = await ref
                              .read(lockerControllerProvider.notifier)
                              .vote(event.id, choice.$1, absenceReason: reason);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  saved
                                      ? '${choice.$1}으로 저장했습니다.'
                                      : '응답을 저장하지 못했습니다.',
                                ),
                              ),
                            );
                          }
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: compact ? 42 : 68,
                    decoration: BoxDecoration(
                      color: active
                          ? choice.$3
                          : choice.$3.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: choice.$3.withValues(alpha: active ? 1 : .25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!compact) ...[
                          Icon(
                            choice.$2,
                            size: 20,
                            color: active ? Colors.white : choice.$3,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          choice.$1,
                          style: TextStyle(
                            color: active ? Colors.white : choice.$3,
                            fontSize: compact ? 12 : 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  IconData _choiceIcon(String value) => switch (value) {
    '참석' => Icons.check_rounded,
    '불참' => Icons.close_rounded,
    '지각' => Icons.schedule_rounded,
    _ => Icons.more_horiz_rounded,
  };

  Color _choiceColor(String value) => switch (value) {
    '참석' => EncbaColors.attending,
    '불참' => EncbaColors.absent,
    '지각' => EncbaColors.late,
    _ => EncbaColors.undecided,
  };

  Future<String?> _askAbsenceReason(BuildContext context) async {
    var typedReason = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('불참 사유'),
        content: TextField(
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          onChanged: (value) => typedReason = value,
          decoration: const InputDecoration(hintText: '불참 사유를 직접 적어 주세요.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final value = typedReason.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    return reason;
  }
}

class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({super.key, this.existing});
  final LockerEvent? existing;

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _memo;
  late final TextEditingController _opponentOne;
  late final TextEditingController _opponentTwo;
  late bool _hasCapacity;
  late double _capacity;
  late EventKind _kind;
  late String _place;
  late String _court;
  late String _team;
  late Set<String> _uniforms;
  late List<String> _pollOptions;
  final _pollOption = TextEditingController();
  late String _visibility;
  late DateTime _start;
  late DateTime _end;
  late bool _preciseMinutes;
  late bool _recurring;
  late bool _responseEnabled;
  late DateTime _responseDeadline;
  bool _deadlineCustomized = false;
  bool _saving = false;

  static const _places = ['71동 종합체육관', '71-1동 신체육관', '900동 기숙사체육관'];
  static const _editableKinds = [
    EventKind.training,
    EventKind.morning,
    EventKind.freeOpen,
    EventKind.pickup,
    EventKind.scrimmage,
    EventKind.threeWay,
  ];
  static const _ibDivisionOneTeams = [
    '농구부',
    '스티즈',
    '그래비티',
    '썬샷',
    '노바스',
    '호바스',
    '새턴OB',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _memo = TextEditingController(text: existing?.memo ?? '');
    _opponentOne = TextEditingController(
      text: existing?.opponents.elementAtOrNull(0) ?? '',
    );
    _opponentTwo = TextEditingController(
      text: existing?.opponents.elementAtOrNull(1) ?? '',
    );
    _hasCapacity = existing?.capacity != null;
    _capacity = (existing?.capacity ?? 20).clamp(2, 60).toDouble();
    _kind = existing?.kind ?? EventKind.training;
    _place = existing?.place.trim().isNotEmpty == true
        ? existing!.place
        : _places.first;
    _court = existing?.court ?? 'A코트';
    _team = switch (existing?.targetTeam) {
      'ENCBA 1부' => 'ENCBA',
      'ENCBA 2부' => 'BEN',
      final value? => value,
      _ => '전체',
    };
    _uniforms = existing?.uniformColors.toSet() ?? <String>{};
    _pollOptions = [
      ...existing?.pollOptions ?? const ['참석', '불참', '미정'],
    ];
    _visibility = existing?.visibility ?? 'team';
    final suggestedStart = DateTime.now().add(
      const Duration(days: 1, hours: 1),
    );
    _start =
        existing?.start ??
        DateTime(
          suggestedStart.year,
          suggestedStart.month,
          suggestedStart.day,
          suggestedStart.hour,
        );
    _end = existing?.end ?? _start.add(const Duration(hours: 2));
    _preciseMinutes =
        existing != null &&
        (existing.start.minute != 0 || existing.end.minute != 0);
    _recurring = existing?.isRecurring ?? false;
    _responseEnabled = true;
    _responseDeadline =
        existing?.responseDeadline ??
        _start.subtract(
          _kind.isMatch ? const Duration(hours: 3) : const Duration(hours: 1),
        );
    _deadlineCustomized = existing?.responseDeadlineOverride != null;
  }

  @override
  void dispose() {
    _memo.dispose();
    _opponentOne.dispose();
    _opponentTwo.dispose();
    _pollOption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final canManage = user?.canAdminister ?? false;
    if (!canManage) {
      return Scaffold(
        appBar: AppBar(title: const Text('일정')),
        body: const Center(child: Text('일정 관리자만 수정할 수 있습니다.')),
      );
    }
    final editing = widget.existing != null;
    final placeOptions = _places.contains(_place)
        ? _places
        : [..._places, _place];
    final kindOptions = _editableKinds.contains(_kind)
        ? _editableKinds
        : [_kind, ..._editableKinds];
    return Scaffold(
      appBar: AppBar(title: Text(editing ? '일정 수정' : '새 일정')),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 34,
          ),
          children: [
            const _FormSectionTitle('기본 정보'),
            const SizedBox(height: 12),
            DropdownButtonFormField<EventKind>(
              initialValue: _kind,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '일정 유형 *',
                helperText: '선택한 유형이 일정 제목으로 표시됩니다.',
              ),
              items: kindOptions
                  .map(
                    (kind) =>
                        DropdownMenuItem(value: kind, child: Text(kind.label)),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                _kind = value!;
                if (!_deadlineCustomized) {
                  _responseDeadline = _start.subtract(
                    _kind.isMatch
                        ? const Duration(hours: 3)
                        : const Duration(hours: 1),
                  );
                }
                if (_kind != EventKind.training &&
                    _kind != EventKind.morning &&
                    _kind != EventKind.freeOpen &&
                    _uniforms.isEmpty) {
                  _uniforms = {'검정', '흰색'};
                }
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _team,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '공개 대상 *'),
              items: const ['전체', 'ENCBA', 'BEN', '신입생']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => _team = value!,
            ),
            if (_kind == EventKind.scrimmage ||
                _kind == EventKind.threeWay) ...[
              const SizedBox(height: 18),
              TextFormField(
                controller: _opponentOne,
                decoration: InputDecoration(
                  labelText: _kind == EventKind.threeWay ? '상대팀 1 *' : '상대팀 *',
                  hintText: 'IB 1부 팀 선택 또는 직접 입력',
                ),
                validator: _required,
              ),
              const SizedBox(height: 8),
              _TeamSuggestionStrip(
                teams: _ibDivisionOneTeams,
                onSelected: (team) {
                  _opponentOne.text = team;
                  setState(() {});
                },
              ),
              if (_kind == EventKind.threeWay) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _opponentTwo,
                  decoration: const InputDecoration(
                    labelText: '상대팀 2 *',
                    hintText: '두 번째 상대팀 직접 입력',
                  ),
                  validator: (value) {
                    final requiredError = _required(value);
                    if (requiredError != null) return requiredError;
                    if (value!.trim() == _opponentOne.text.trim()) {
                      return '서로 다른 팀을 입력해 주세요.';
                    }
                    return null;
                  },
                ),
              ],
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _memo,
              minLines: 2,
              maxLines: 5,
              scrollPadding: const EdgeInsets.only(bottom: 160),
              decoration: const InputDecoration(
                labelText: '공지 메모',
                hintText: '필요한 안내가 있을 때만 적어 주세요.',
              ),
            ),
            const SizedBox(height: 24),
            const _FormSectionTitle('시간과 장소'),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('정각')),
                ButtonSegment(value: true, label: Text('분 설정')),
              ],
              selected: {_preciseMinutes},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                final precise = selection.first;
                setState(() {
                  _preciseMinutes = precise;
                  if (!precise) {
                    _start = DateTime(
                      _start.year,
                      _start.month,
                      _start.day,
                      _start.hour,
                    );
                    _end = DateTime(_end.year, _end.month, _end.day, _end.hour);
                    if (!_deadlineCustomized) {
                      _responseDeadline = _start.subtract(
                        _kind.isMatch
                            ? const Duration(hours: 3)
                            : const Duration(hours: 1),
                      );
                    }
                  }
                });
              },
            ),
            const SizedBox(height: 6),
            Text(
              _preciseMinutes ? '시와 분을 정합니다.' : '분을 생략하고 정각으로 등록합니다.',
              style: const TextStyle(color: EncbaColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DateTimeButton(
                    label: '시작',
                    value: _start,
                    showMinutes: _preciseMinutes,
                    onTap: () => _pickDateTime(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateTimeButton(
                    label: '종료',
                    value: _end,
                    showMinutes: _preciseMinutes,
                    onTap: () => _pickDateTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _place,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '장소 *'),
              items: placeOptions
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _place = value!),
            ),
            if (_place == _places.first) ...[
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'A코트', label: Text('A코트')),
                  ButtonSegment(value: 'B코트', label: Text('B코트')),
                  ButtonSegment(value: '전체', label: Text('전체')),
                ],
                selected: {_court},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _court = value.first),
              ),
            ],
            const SizedBox(height: 24),
            const _FormSectionTitle('운영 설정'),
            const SizedBox(height: 12),
            _CapacitySelector(
              enabled: _hasCapacity,
              value: _capacity,
              onEnabledChanged: (value) => setState(() => _hasCapacity = value),
              onChanged: (value) => setState(() => _capacity = value),
            ),
            if (_kind != EventKind.training &&
                _kind != EventKind.morning &&
                _kind != EventKind.freeOpen) ...[
              const SizedBox(height: 14),
              const Text('유니폼 색 *'),
              const SizedBox(height: 8),
              _UniformSelector(
                selected: _uniformSelection,
                onSelected: (value) => setState(() {
                  _uniforms = switch (value) {
                    '검' => {'검정'},
                    '흰' => {'흰색'},
                    _ => {'검정', '흰색'},
                  };
                }),
              ),
            ],
            const SizedBox(height: 18),
            const Text('투표 항목 *'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: _pollOptions
                  .map(
                    (option) => InputChip(
                      label: Text(option),
                      avatar: const Icon(Icons.edit_outlined, size: 15),
                      onPressed: () => _editPollOption(option),
                      onDeleted: _pollOptions.length <= 2
                          ? null
                          : () => setState(() => _pollOptions.remove(option)),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pollOption,
                    decoration: const InputDecoration(hintText: '새 투표 항목'),
                  ),
                ),
                IconButton(
                  tooltip: '투표 항목 추가',
                  onPressed: () {
                    final value = _pollOption.text.trim();
                    if (value.isNotEmpty &&
                        !_pollOptions.contains(value) &&
                        _pollOptions.length < 8) {
                      setState(() => _pollOptions.add(value));
                      _pollOption.clear();
                    }
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            if (_kind == EventKind.external) ...[
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _visibility == 'confirmed_roster',
                onChanged: (value) => setState(
                  () => _visibility = value ? 'confirmed_roster' : 'team',
                ),
                title: const Text('확정 출전 인원만 상세 공개'),
                subtitle: const Text('다른 부원에게는 잠긴 경기로 표시합니다.'),
              ),
            ],
            const SizedBox(height: 14),
            _DateTimeButton(
              label: '마감 정하기',
              value: _responseDeadline,
              onTap: _pickResponseDeadline,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _deadlineCustomized
                        ? '직접 정한 마감 시간입니다.'
                        : _kind.isMatch
                        ? '기본값 · 경기 시작 3시간 전'
                        : '기본값 · 일정 시작 1시간 전',
                    style: const TextStyle(
                      color: EncbaColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (_deadlineCustomized)
                  TextButton(
                    onPressed: () => setState(() {
                      _deadlineCustomized = false;
                      _responseDeadline = _start.subtract(
                        _kind.isMatch
                            ? const Duration(hours: 3)
                            : const Duration(hours: 1),
                      );
                    }),
                    child: const Text('기본값'),
                  ),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _recurring,
              onChanged: _kind == EventKind.training && widget.existing == null
                  ? (value) => setState(() => _recurring = value)
                  : null,
              title: const Text('매주 반복'),
              subtitle: Text(
                widget.existing == null
                    ? '정기훈련 12회를 생성하며 각 일정은 따로 수정할 수 있습니다.'
                    : '반복 설정은 최초 등록할 때만 선택할 수 있습니다.',
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? '저장 중…'
                    : editing
                    ? '변경 내용 저장'
                    : '일정 등록',
              ),
            ),
            if (editing) ...[
              const SizedBox(height: 10),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: EncbaColors.absent,
                ),
                onPressed: _delete,
                child: const Text('일정 삭제'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _uniformSelection {
    if (_uniforms.contains('검정') && _uniforms.contains('흰색')) return '모두';
    if (_uniforms.contains('흰색')) return '흰';
    return '검';
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '필수 항목입니다.' : null;

  Future<void> _pickDateTime(bool start) async {
    final current = start ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (!mounted || date == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted || pickedTime == null) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      pickedTime.hour,
      _preciseMinutes ? pickedTime.minute : 0,
    );
    setState(() {
      if (start) {
        _start = value;
        if (_end.isBefore(value)) _end = value.add(const Duration(hours: 2));
        if (!_deadlineCustomized) {
          _responseDeadline = value.subtract(
            _kind.isMatch ? const Duration(hours: 3) : const Duration(hours: 1),
          );
        }
      } else {
        _end = value;
      }
    });
  }

  Future<void> _pickResponseDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _responseDeadline,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: _start,
    );
    if (!mounted || date == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_responseDeadline),
    );
    if (!mounted || pickedTime == null) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (value.isAfter(_start)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('응답 마감은 일정 시작 전이어야 합니다.')));
      return;
    }
    setState(() {
      _responseDeadline = value;
      _deadlineCustomized = true;
    });
  }

  Future<void> _editPollOption(String option) async {
    final controller = TextEditingController(text: option);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('투표 항목 수정'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: '투표 항목'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || edited == null || edited.isEmpty) return;
    if (_pollOptions.contains(edited) && edited != option) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미 같은 투표 항목이 있습니다.')));
      return;
    }
    setState(() {
      final index = _pollOptions.indexOf(option);
      if (index >= 0) _pollOptions[index] = edited;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('종료 시간은 시작 시간보다 늦어야 합니다.')));
      return;
    }
    if (_responseDeadline.isAfter(_start)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('응답 마감은 일정 시작 전이어야 합니다.')));
      return;
    }
    if (_kind != EventKind.training &&
        _kind != EventKind.morning &&
        _kind != EventKind.freeOpen &&
        _uniforms.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('경기 유니폼 색을 하나 이상 선택해 주세요.')));
      return;
    }
    setState(() => _saving = true);
    final user = ref.read(authControllerProvider).user;
    final event = LockerEvent(
      id:
          widget.existing?.id ??
          'event-${DateTime.now().microsecondsSinceEpoch}',
      title: _kind.label,
      start: _start,
      end: _end,
      place: _place,
      court: _place == _places.first ? _court : null,
      kind: _kind,
      memo: _memo.text.trim(),
      uniformColors: _uniforms.toList(),
      capacity: _hasCapacity ? _capacity.round() : null,
      attending: widget.existing?.attending ?? 0,
      targetTeam: _team,
      createdBy: widget.existing?.createdBy ?? '운영진 ${user?.name ?? ''}',
      updatedAt: '방금 전',
      isRecurring: _kind == EventKind.training && _recurring,
      responseEnabled: _responseEnabled,
      responseDeadlineOverride: _responseDeadline,
      pollOptions: _pollOptions,
      visibility: _visibility,
      opponents: switch (_kind) {
        EventKind.scrimmage => [_opponentOne.text.trim()],
        EventKind.threeWay => [
          _opponentOne.text.trim(),
          _opponentTwo.text.trim(),
        ],
        _ => const [],
      },
    );
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .saveEvent(event);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('일정을 삭제할까요?'),
        content: const Text('이 기기에 저장된 일정과 참석 응답이 더 이상 표시되지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: EncbaColors.absent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final deleted = await ref
        .read(lockerControllerProvider.notifier)
        .deleteEvent(widget.existing!.id);
    if (mounted && deleted) {
      Navigator.pop(context);
      Navigator.pop(context);
    }
  }
}

class EventKindLabel extends StatelessWidget {
  const EventKindLabel({super.key, required this.kind, this.inverted = false});
  final EventKind kind;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final color = _kindColor(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: inverted
            ? Colors.white.withValues(alpha: .12)
            : color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        kind.label,
        style: TextStyle(
          color: inverted ? Colors.white : color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TeamSuggestionStrip extends StatelessWidget {
  const _TeamSuggestionStrip({required this.teams, required this.onSelected});
  final List<String> teams;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: teams.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) => ActionChip(
        visualDensity: VisualDensity.compact,
        label: Text(teams[index]),
        onPressed: () => onSelected(teams[index]),
      ),
    ),
  );
}

class _CapacitySelector extends StatelessWidget {
  const _CapacitySelector({
    required this.enabled,
    required this.value,
    required this.onEnabledChanged,
    required this.onChanged,
  });

  final bool enabled;
  final double value;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: EncbaColors.line),
      borderRadius: BorderRadius.circular(16),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 10, 12),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            title: const Text('인원 제한'),
            subtitle: Text(enabled ? '${value.round()}명까지' : '제한 없음'),
            onChanged: onEnabledChanged,
          ),
          if (enabled)
            LayoutBuilder(
              builder: (context, constraints) {
                const badgeWidth = 58.0;
                final progress = (value - 2) / 58;
                final badgeLeft =
                    (progress * (constraints.maxWidth - 28) -
                            badgeWidth / 2 +
                            14)
                        .clamp(0.0, constraints.maxWidth - badgeWidth)
                        .toDouble();
                return Column(
                  children: [
                    SizedBox(
                      height: 30,
                      child: Stack(
                        children: [
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 100),
                            left: badgeLeft,
                            top: 0,
                            width: badgeWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: EncbaColors.navy,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Text(
                                  '${value.round()}명',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 24, child: Text('2')),
                        Expanded(
                          child: Slider(
                            value: value,
                            min: 2,
                            max: 60,
                            divisions: 58,
                            onChanged: onChanged,
                          ),
                        ),
                        const SizedBox(
                          width: 30,
                          child: Text('60', textAlign: TextAlign.right),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    ),
  );
}

class _UniformSelector extends StatelessWidget {
  const _UniformSelector({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFFE7ECF3),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: ['검', '흰', '모두'].map((label) {
        final active = selected == label;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelected(label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: active ? EncbaColors.navy : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: active ? Colors.white : EncbaColors.ink,
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

class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    required this.label,
    required this.value,
    required this.onTap,
    this.showMinutes = true,
  });
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  final bool showMinutes;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: EncbaColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 3),
        Text(
          showMinutes
              ? DateFormat('M.d  HH:mm').format(value)
              : '${DateFormat('M.d').format(value)}  ${value.hour}시',
        ),
      ],
    ),
  );
}

class _FormSectionTitle extends StatelessWidget {
  const _FormSectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.icon,
    required this.text,
    this.color = EncbaColors.muted,
    this.emphasized = false,
    this.markerColor,
  });
  final IconData icon;
  final String text;
  final Color color;
  final bool emphasized;
  final Color? markerColor;
  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: emphasized ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(icon, color: color, size: emphasized ? 19 : 18),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: emphasized ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: emphasized ? 'Jua' : null,
              color: color,
              fontSize: emphasized ? 15 : 13,
              height: 1.25,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
    if (!emphasized) return content;
    return Align(
      alignment: Alignment.centerLeft,
      child: CustomPaint(
        painter: _MarkerPainter(markerColor ?? EncbaColors.placeMarker),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 5, 10, 5),
          child: content,
        ),
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .82)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(1, size.height * .18)
      ..lineTo(size.width - 3, 0)
      ..lineTo(size.width, size.height * .82)
      ..lineTo(4, size.height)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * .72, size.width, size.height * .18),
      Paint()..color = color.withValues(alpha: .35),
    );
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter oldDelegate) =>
      oldDelegate.color != color;
}

Color _kindColor(EventKind kind) => switch (kind) {
  EventKind.training => EncbaColors.snuBlue,
  EventKind.morning => EncbaColors.attending,
  EventKind.freeOpen => const Color(0xFF2A7C67),
  EventKind.internal => EncbaColors.deepBlue,
  EventKind.pickup => EncbaColors.deepBlue,
  EventKind.ibDivision1 ||
  EventKind.ibDivision2 ||
  EventKind.ibFreshman => const Color(0xFF6D43A6),
  EventKind.scrimmage ||
  EventKind.threeWay ||
  EventKind.external => EncbaColors.absent,
  EventKind.operations => EncbaColors.late,
  EventKind.homecoming => const Color(0xFFB06C20),
};

String time(DateTime value) => DateFormat('HH:mm').format(value);
String weekday(DateTime value) =>
    const ['월', '화', '수', '목', '금', '토', '일'][value.weekday - 1];

Future<void> _openMap(BuildContext context, LockerEvent event) async {
  const places = {
    '71동 종합체육관':
        'https://map.naver.com/p/entry/place/18733898?c=15.00,0,0,0,dh',
    '71-1동 신체육관':
        'https://map.naver.com/p/entry/place/1985573410?c=15.00,0,0,0,dh',
    '900동 기숙사체육관':
        'https://map.naver.com/p/search/%EC%84%9C%EC%9A%B8%EB%8C%80%EA%B8%B0%EC%88%99%EC%82%AC900%EB%8F%99/place/1289118439?c=15.00,0,0,0,dh',
  };
  final uri = Uri.parse(
    places[event.place] ??
        'https://map.naver.com/p/search/${Uri.encodeComponent(event.fullPlace)}',
  );
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('네이버 지도를 열 수 없습니다.')));
  }
}

Future<void> _addCalendar(BuildContext context, LockerEvent event) async {
  final success = await addEventToCalendar(event);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(success ? '캘린더 추가 화면을 열었습니다.' : '이 기기에서는 캘린더를 열 수 없습니다.'),
    ),
  );
}
