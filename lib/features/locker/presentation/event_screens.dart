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
    final isAdmin = ref.watch(authControllerProvider).user?.isAdmin ?? false;
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
          const SizedBox(height: 22),
          Text('안내', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 9),
          Text(event.memo, style: const TextStyle(height: 1.7)),
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
              if (event.uniformColor != null)
                Text(
                  '${event.uniformColor} 유니폼',
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
        ref.watch(lockerControllerProvider).attendance[event.id] ??
        AttendanceStatus.undecided;
    final isAdmin = ref.watch(authControllerProvider).user?.isAdmin ?? false;
    final isClosed = DateTime.now().isAfter(event.responseDeadline) && !isAdmin;
    const choices = [
      (
        AttendanceStatus.attending,
        '참석',
        Icons.check_rounded,
        EncbaColors.attending,
      ),
      (AttendanceStatus.late, '지각', Icons.schedule_rounded, EncbaColors.late),
      (AttendanceStatus.absent, '불참', Icons.close_rounded, EncbaColors.absent),
      (
        AttendanceStatus.undecided,
        '미정',
        Icons.more_horiz_rounded,
        EncbaColors.undecided,
      ),
    ];
    return Row(
      children: choices.map((choice) {
        final active = selected == choice.$1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: choice.$1 == AttendanceStatus.undecided ? 0 : 7,
            ),
            child: Semantics(
              selected: active,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: isClosed
                    ? null
                    : () async {
                        final saved = await ref
                            .read(lockerControllerProvider.notifier)
                            .vote(event.id, choice.$1);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                saved
                                    ? '${choice.$2}으로 저장했습니다.'
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
                        ? choice.$4
                        : choice.$4.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: choice.$4.withValues(alpha: active ? 1 : .25),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!compact) ...[
                        Icon(
                          choice.$3,
                          size: 20,
                          color: active ? Colors.white : choice.$4,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        choice.$2,
                        style: TextStyle(
                          color: active ? Colors.white : choice.$4,
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
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
  late final TextEditingController _title;
  late final TextEditingController _memo;
  late final TextEditingController _capacity;
  late EventKind _kind;
  late String _place;
  late String _court;
  late String _team;
  late String _uniform;
  late DateTime _start;
  late DateTime _end;
  late bool _recurring;
  late bool _responseEnabled;
  bool _saving = false;

  static const _places = ['71동 종합체육관', '71-1동 신체육관', '900동 기숙사체육관'];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _memo = TextEditingController(text: existing?.memo ?? '');
    _capacity = TextEditingController(
      text: existing?.capacity?.toString() ?? '',
    );
    _kind = existing?.kind ?? EventKind.training;
    _place = existing?.place.trim().isNotEmpty == true
        ? existing!.place
        : _places.first;
    _court = existing?.court ?? 'A코트';
    _team = existing?.targetTeam ?? '전체';
    _uniform = existing?.uniformColor ?? '없음';
    _start =
        existing?.start ??
        DateTime.now().add(const Duration(days: 1, hours: 1));
    _end = existing?.end ?? _start.add(const Duration(hours: 2));
    _recurring = existing?.isRecurring ?? false;
    _responseEnabled = existing?.responseEnabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _memo.dispose();
    _capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authControllerProvider).user?.isAdmin ?? false;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('일정')),
        body: const Center(child: Text('관리자만 수정할 수 있습니다.')),
      );
    }
    final editing = widget.existing != null;
    final placeOptions = _places.contains(_place)
        ? _places
        : [..._places, _place];
    return Scaffold(
      appBar: AppBar(title: Text(editing ? '일정 수정' : '새 일정')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
          children: [
            const _FormSectionTitle('기본 정보'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: '제목 *',
                hintText: '예: 정기 훈련',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<EventKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: '유형 *'),
              items: EventKind.values
                  .map(
                    (kind) =>
                        DropdownMenuItem(value: kind, child: Text(kind.label)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _kind = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _team,
              decoration: const InputDecoration(labelText: '공개 대상 *'),
              items: const ['전체', 'ENCBA', 'BEN', 'ENCBA 1부', 'ENCBA 2부']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => _team = value!,
            ),
            const SizedBox(height: 24),
            const _FormSectionTitle('시간과 장소'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateTimeButton(
                    label: '시작',
                    value: _start,
                    onTap: () => _pickDateTime(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateTimeButton(
                    label: '종료',
                    value: _end,
                    onTap: () => _pickDateTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _place,
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
            TextFormField(
              controller: _memo,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '공지 메모 *',
                hintText: '집합 시간과 준비물을 적어 주세요.',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _capacity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '인원 제한',
                      hintText: '선택',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _uniform,
                    decoration: const InputDecoration(labelText: '유니폼'),
                    items: const ['없음', '검정', '흰색']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => _uniform = value!,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _responseEnabled,
              onChanged: (value) => setState(() => _responseEnabled = value),
              title: const Text('참석 응답 받기'),
              subtitle: Text(
                _kind.isMatch ? '경기 시작 3시간 전 마감' : '훈련 시작 1시간 전 마감',
              ),
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
      pickedTime.minute,
    );
    setState(() {
      if (start) {
        _start = value;
        if (_end.isBefore(value)) _end = value.add(const Duration(hours: 2));
      } else {
        _end = value;
      }
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
    setState(() => _saving = true);
    final user = ref.read(authControllerProvider).user;
    final event = LockerEvent(
      id:
          widget.existing?.id ??
          'event-${DateTime.now().microsecondsSinceEpoch}',
      title: _title.text.trim(),
      start: _start,
      end: _end,
      place: _place,
      court: _place == _places.first ? _court : null,
      kind: _kind,
      memo: _memo.text.trim(),
      uniformColor: _uniform == '없음' ? null : _uniform,
      capacity: int.tryParse(_capacity.text.trim()),
      attending: widget.existing?.attending ?? 0,
      targetTeam: _team,
      createdBy: widget.existing?.createdBy ?? '운영진 ${user?.name ?? ''}',
      updatedAt: '방금 전',
      isRecurring: _kind == EventKind.training && _recurring,
      responseEnabled: _responseEnabled,
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

class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final DateTime value;
  final VoidCallback onTap;

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
        Text(DateFormat('M.d  HH:mm').format(value)),
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
  EventKind.internal => EncbaColors.deepBlue,
  EventKind.ibDivision1 || EventKind.ibDivision2 => const Color(0xFF6D43A6),
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
