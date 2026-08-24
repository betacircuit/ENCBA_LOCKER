import 'dart:async';
import 'dart:math' as math;

import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/services/calendar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

part 'event_editor_screen.dart';

final Map<String, int> _attendanceUiRevisions = {};

Future<void> openEventDetail(
  BuildContext context,
  String eventId, {
  String heroTagPrefix = 'event',
}) {
  return context.push<void>(
    '/schedule/${Uri.encodeComponent(eventId)}',
    extra: '$heroTagPrefix-$eventId',
  );
}

typedef _EventBuilder = Widget Function(LockerEvent event);

/// 주소의 ID를 현재 상태에서 찾고, 초기 페이지에 없으면 서버에서 한 건만 읽는다.
class _EventResolver extends ConsumerStatefulWidget {
  const _EventResolver({required this.eventId, required this.builder});

  final String eventId;
  final _EventBuilder builder;

  @override
  ConsumerState<_EventResolver> createState() => _EventResolverState();
}

class _EventResolverState extends ConsumerState<_EventResolver> {
  bool _loading = true;
  bool _notFound = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(_EventResolver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) {
      _loading = true;
      _notFound = false;
      _error = null;
      Future.microtask(_load);
    }
  }

  Future<void> _load() async {
    try {
      final found = await ref
          .read(lockerControllerProvider.notifier)
          .ensureEvent(widget.eventId);
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
    final plannerState = ref.watch(
      lockerControllerProvider.select(
        (state) => (
          events: state.eventsState.events,
          operations: state.operationsState.operations,
        ),
      ),
    );
    final event = <LockerEvent>[
      ...plannerState.events,
      ...plannerState.operations.map((item) => item.toPlannerEvent()),
    ].where((item) => item.id == widget.eventId).firstOrNull;
    if (event != null) return widget.builder(event);
    return _EntityLoadScaffold(
      title: '일정',
      loading: _loading,
      notFound: _notFound,
      error: _error,
      onRetry: () {
        setState(() {
          _loading = true;
          _notFound = false;
          _error = null;
        });
        _load();
      },
    );
  }
}

class _EntityLoadScaffold extends StatelessWidget {
  const _EntityLoadScaffold({
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
    final uniformDecoration = _uniformCardDecoration(event);
    if (event.isLocked) {
      return Semantics(
        button: true,
        label:
            '${event.title}, ${event.start.month}월 ${event.start.day}일, 출전 명단 확정 후 공개',
        excludeSemantics: true,
        child: Material(
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
        ),
      );
    }
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: EncbaColors.line),
      ),
      child: Column(
        children: [
          Ink(
            decoration: BoxDecoration(
              color: uniformDecoration.color,
              gradient: uniformDecoration.gradient,
            ),
            child: Semantics(
              button: true,
              label:
                  '${event.title}, ${event.start.month}월 ${event.start.day}일, ${time(event.start)}부터 ${time(event.end)}까지, ${event.fullPlace}',
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(width: 7, color: accent),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 15 : 19),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  EventKindLabel(
                                    kind: event.kind,
                                    inverted:
                                        uniformDecoration.dark ||
                                        uniformDecoration.split,
                                  ),
                                ],
                              ),
                              SizedBox(height: compact ? 10 : 16),
                              _UniformCardForeground(
                                decoration: uniformDecoration,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
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
                                        ),
                                      ),
                                      if (event.opponents.isNotEmpty) ...[
                                        const SizedBox(height: 5),
                                        Text(
                                          'vs ${event.opponents.join(' · ')}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      _MetaLine(
                                        icon: Icons.calendar_today_outlined,
                                        text:
                                            '${event.start.month}월 ${event.start.day}일 (${weekday(event.start)}) · ${time(event.start)}–${time(event.end)}',
                                        color: uniformDecoration.dark
                                            ? Colors.white
                                            : EncbaColors.ink,
                                      ),
                                      const SizedBox(height: 7),
                                      _MetaLine(
                                        icon: Icons.location_on_outlined,
                                        text: event.fullPlace,
                                        color: uniformDecoration.dark
                                            ? Colors.white
                                            : EncbaColors.ink,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 15,
                          color: uniformDecoration.dark
                              ? Colors.white70
                              : EncbaColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (event.responseEnabled) ...[
            const Divider(height: 1),
            AttendanceSelector(event: event, compact: true, flush: true),
          ],
        ],
      ),
    );
  }
}

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) => _EventResolver(
    eventId: eventId,
    builder: (event) => _EventDetailView(initialEvent: event),
  );
}

class _EventDetailView extends ConsumerStatefulWidget {
  const _EventDetailView({required this.initialEvent});

  final LockerEvent initialEvent;

  @override
  ConsumerState<_EventDetailView> createState() => _EventDetailViewState();
}

class _EventDetailViewState extends ConsumerState<_EventDetailView> {
  @override
  void initState() {
    super.initState();
    if (!widget.initialEvent.id.startsWith('operation-')) {
      Future.microtask(() async {
        final controller = ref.read(lockerControllerProvider.notifier);
        await Future.wait([
          controller.loadEventAttendance(widget.initialEvent.id),
          controller.loadEventStrategy(widget.initialEvent.id),
        ]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventState = ref.watch(
      lockerControllerProvider.select(
        (state) => (
          events: state.eventsState.events,
          responses: state.eventsState.eventAttendance[widget.initialEvent.id],
          strategy: state.eventsState.eventStrategies[widget.initialEvent.id],
        ),
      ),
    );
    final events = eventState.events;
    final members = ref.watch(
      lockerControllerProvider.select((state) => state.membersState.members),
    );
    final event =
        events.where((item) => item.id == widget.initialEvent.id).firstOrNull ??
        widget.initialEvent;
    final responses = eventState.responses ?? const <AttendanceResponse>[];
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
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
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
          if (isAdmin && event.kind != EventKind.operations)
            IconButton(
              tooltip: '일정 수정',
              onPressed: () => context.push(
                '/schedule/${Uri.encodeComponent(event.id)}/edit',
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
          const SizedBox(height: 18),
          _EventDetailFacts(event: event),
          if (event.memo.trim().isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('안내', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 9),
            Text(event.memo, style: const TextStyle(height: 1.7)),
          ],
          if (event.starterNames.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('주전', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: event.starterNames
                  .map(
                    (name) => Chip(
                      avatar: const Icon(Icons.sports_basketball, size: 16),
                      label: Text(name),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (event.kind.isMatch) ...[
            const SizedBox(height: 22),
            _StrategyCard(
              event: event,
              strategy: eventState.strategy ?? EventStrategy(eventId: event.id),
            ),
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
                child: FilledButton.icon(
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
              onPressed: () => context.push(
                '/schedule/${Uri.encodeComponent(event.id)}/roster',
              ),
              icon: const Icon(Icons.how_to_reg_outlined),
              label: const Text('출전 명단 확정'),
            ),
          ],
          if (event.responseEnabled) ...[
            const SizedBox(height: 22),
            _AttendanceResponseCard(
              event: event,
              responses: responses,
              members: members,
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

class _AttendanceResponseCard extends StatelessWidget {
  const _AttendanceResponseCard({
    required this.event,
    required this.responses,
    required this.members,
  });

  final LockerEvent event;
  final List<AttendanceResponse> responses;
  final List<MemberProfile> members;

  @override
  Widget build(BuildContext context) {
    final options = <String>[
      ...event.pollOptions,
      ...responses
          .map((response) => response.choice)
          .where((choice) => !event.pollOptions.contains(choice)),
    ];
    final uniqueOptions = options.toSet().toList(growable: false);
    final responseNames = responses
        .map((response) => response.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final unansweredNames =
        members
            .where((member) => member.isActive)
            .map((member) => member.name.trim())
            .where((name) => name.isNotEmpty && !responseNames.contains(name))
            .toSet()
            .toList(growable: false)
          ..sort();

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: EncbaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 13),
            child: Row(
              children: [
                Text('참석 현황', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Text(
                  '${responses.length}명 응답',
                  style: const TextStyle(
                    color: EncbaColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (responses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '아직 응답이 없습니다.',
                style: TextStyle(color: EncbaColors.muted),
              ),
            )
          else
            ...uniqueOptions.indexed.map((entry) {
              final option = entry.$2;
              final optionResponses =
                  responses
                      .where((response) => response.choice == option)
                      .toList(growable: false)
                    ..sort((a, b) => a.name.compareTo(b.name));
              return _AttendanceOptionRow(
                index: entry.$1 + 1,
                option: option,
                responses: optionResponses,
                totalResponses: responses.length,
                showDivider: entry.$1 > 0,
              );
            }),
          if (unansweredNames.isNotEmpty) ...[
            const Divider(height: 1),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 18),
                childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 17),
                title: Text(
                  '미응답 ${unansweredNames.length}명',
                  style: const TextStyle(
                    color: EncbaColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      unansweredNames.join(', '),
                      style: const TextStyle(
                        color: EncbaColors.muted,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttendanceOptionRow extends StatelessWidget {
  const _AttendanceOptionRow({
    required this.index,
    required this.option,
    required this.responses,
    required this.totalResponses,
    required this.showDivider,
  });

  final int index;
  final String option;
  final List<AttendanceResponse> responses;
  final int totalResponses;
  final bool showDivider;

  Color get _color => switch (option) {
    '참석' => EncbaColors.attending,
    '불참' => EncbaColors.absent,
    '지각' => EncbaColors.late,
    '미정' => EncbaColors.undecided,
    _ => EncbaColors.deepBlue,
  };

  @override
  Widget build(BuildContext context) {
    final names = responses.map((response) => response.name).join(', ');
    final reasons = responses
        .where((response) => response.absenceReason?.trim().isNotEmpty ?? false)
        .toList(growable: false);
    final ratio = totalResponses == 0 ? 0.0 : responses.length / totalResponses;

    return Column(
      children: [
        if (showDivider) const Divider(height: 1, indent: 60),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 18, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _color.withValues(alpha: .12),
                child: Text(
                  '$index',
                  style: TextStyle(color: _color, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            option,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${responses.length}',
                          style: TextStyle(
                            color: _color,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        color: _color,
                        backgroundColor: EncbaColors.line,
                      ),
                    ),
                    if (names.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Text(
                        names,
                        style: const TextStyle(
                          color: EncbaColors.muted,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (reasons.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...reasons.map(
                        (response) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${response.name} · ${response.absenceReason!.trim()}',
                            style: const TextStyle(
                              color: EncbaColors.ink,
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StrategyCard extends ConsumerWidget {
  const _StrategyCard({required this.event, required this.strategy});

  final LockerEvent event;
  final EventStrategy strategy;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5FA),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: EncbaColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.draw_outlined, color: EncbaColors.snuBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '전술 · 전략',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => _edit(context, ref),
              child: Text(strategy.isEmpty ? '전술 짜기' : '수정'),
            ),
          ],
        ),
        if (strategy.isEmpty)
          const Text(
            '공격과 수비 약속을 팀원들과 공유해 보세요.',
            style: TextStyle(color: EncbaColors.muted),
          )
        else ...[
          if (strategy.offense.isNotEmpty)
            _StrategyLine('공격', strategy.offense),
          if (strategy.defense.isNotEmpty)
            _StrategyLine('수비', strategy.defense),
          if (strategy.notes.isNotEmpty) _StrategyLine('메모', strategy.notes),
          if (strategy.updatedBy.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              '${strategy.updatedBy} 수정',
              style: const TextStyle(color: EncbaColors.muted, fontSize: 11),
            ),
          ],
        ],
      ],
    ),
  );

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final offense = TextEditingController(text: strategy.offense);
    final defense = TextEditingController(text: strategy.defense);
    final notes = TextEditingController(text: strategy.notes);
    final result = await showModalBottomSheet<EventStrategy>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '전술 · 전략',
                  style: TextStyle(
                    fontFamily: 'Jua',
                    fontSize: 25,
                    color: EncbaColors.navy,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: offense,
                  minLines: 2,
                  maxLines: 5,
                  scrollPadding: const EdgeInsets.only(bottom: 220),
                  decoration: const InputDecoration(
                    labelText: '공격',
                    hintText: '세트 오펜스, 스크린 약속, 첫 옵션',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: defense,
                  minLines: 2,
                  maxLines: 5,
                  scrollPadding: const EdgeInsets.only(bottom: 180),
                  decoration: const InputDecoration(
                    labelText: '수비',
                    hintText: '매치업, 헬프 위치, 리바운드 약속',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 5,
                  scrollPadding: const EdgeInsets.only(bottom: 140),
                  decoration: const InputDecoration(
                    labelText: '추가 메모',
                    hintText: '타임아웃 때 확인할 한 문장',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    sheetContext,
                    EventStrategy(
                      eventId: event.id,
                      offense: offense.text,
                      defense: defense.text,
                      notes: notes.text,
                    ),
                  ),
                  child: const Text('전술 저장'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    offense.dispose();
    defense.dispose();
    notes.dispose();
    if (result == null) return;
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .saveEventStrategy(result);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(saved ? '전술을 저장했습니다.' : '전술 저장에 실패했습니다.')),
        );
    }
  }
}

class _StrategyLine extends StatelessWidget {
  const _StrategyLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: const TextStyle(
              color: EncbaColors.snuBlue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(height: 1.5))),
      ],
    ),
  );
}

class EventRosterScreen extends StatelessWidget {
  const EventRosterScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) => _EventResolver(
    eventId: eventId,
    builder: (event) => _EventRosterView(event: event),
  );
}

class _EventRosterView extends ConsumerStatefulWidget {
  const _EventRosterView({required this.event});

  final LockerEvent event;

  @override
  ConsumerState<_EventRosterView> createState() => _EventRosterViewState();
}

class _EventRosterViewState extends ConsumerState<_EventRosterView> {
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
        ref.watch(
          lockerControllerProvider.select(
            (state) => state.eventsState.eventRosters[widget.event.id],
          ),
        ) ??
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
    const detailBackground = EncbaColors.navy;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: detailBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: detailBackground),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EventKindLabel(kind: event.kind, inverted: true),
              const Spacer(),
              if (event.uniformColors.isNotEmpty)
                Text(
                  '${event.uniformColors.join(' · ')} 유니폼',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            event.title,
            style: TextStyle(
              fontFamily: encbaFontFor(event.title, display: true),
              color: Colors.white,
              fontSize: 32,
              height: 1.1,
            ),
          ),
          if (event.opponents.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'vs ${event.opponents.join(' · ')}',
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
          const SizedBox(height: 18),
          _MetaLine(
            icon: Icons.calendar_today_outlined,
            text:
                '${event.start.month}월 ${event.start.day}일 (${weekday(event.start)}) · ${time(event.start)}–${time(event.end)}',
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
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (event.obParticipantCount > 0) ...[
            const SizedBox(height: 5),
            Text(
              'OB ${event.obParticipantCount}명 참여',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _EventDetailFacts extends StatelessWidget {
  const _EventDetailFacts({required this.event});

  final LockerEvent event;

  @override
  Widget build(BuildContext context) {
    final opponent = event.opponents.isEmpty
        ? '미정'
        : event.opponents.join(' · ');
    final uniform = event.uniformColors.isEmpty
        ? '미정'
        : event.uniformColors.join(' · ');
    final dateTime =
        '${event.start.year}년 ${event.start.month}월 ${event.start.day}일 '
        '(${weekday(event.start)}) ${time(event.start)}–${time(event.end)}';

    return Semantics(
      container: true,
      label: '일정 정보',
      child: Container(
        key: const ValueKey('event-detail-facts'),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: EncbaColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('일정 정보', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            _EventDetailFactRow(
              icon: Icons.groups_2_outlined,
              label: '상대',
              value: opponent,
            ),
            const SizedBox(height: 12),
            _EventDetailFactRow(
              icon: Icons.checkroom_outlined,
              label: '유니폼',
              value: uniform,
            ),
            const SizedBox(height: 12),
            _EventDetailFactRow(
              icon: Icons.schedule_outlined,
              label: '일시',
              value: dateTime,
            ),
            const SizedBox(height: 12),
            _EventDetailFactRow(
              icon: Icons.location_on_outlined,
              label: '장소',
              value: event.fullPlace,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventDetailFactRow extends StatelessWidget {
  const _EventDetailFactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: EncbaColors.snuBlue),
      const SizedBox(width: 10),
      SizedBox(
        width: 50,
        child: Text(
          label,
          style: const TextStyle(
            color: EncbaColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
        ),
      ),
    ],
  );
}

class AttendanceSelector extends ConsumerWidget {
  const AttendanceSelector({
    super.key,
    required this.event,
    this.compact = false,
    this.flush = false,
  });
  final LockerEvent event;
  final bool compact;
  final bool flush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      lockerControllerProvider.select(
        (state) => state.eventsState.attendance[event.id],
      ),
    );
    final isAdmin =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    final isClosed = DateTime.now().isAfter(event.responseDeadline) && !isAdmin;
    final choices = event.pollOptions
        .map((label) => (label, _choiceIcon(label), _choiceColor(label)))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = choices.length <= 4 ? choices.length : 2;
        final spacing = flush ? 0.0 : 7.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: choices.map((choice) {
            final active = selected == choice.$1;
            return SizedBox(
              width: width,
              child: Semantics(
                selected: active,
                button: true,
                child: InkWell(
                  borderRadius: flush
                      ? BorderRadius.zero
                      : BorderRadius.circular(13),
                  onTap: isClosed
                      ? null
                      : () async {
                          final revision =
                              (_attendanceUiRevisions[event.id] ?? 0) + 1;
                          _attendanceUiRevisions[event.id] = revision;
                          String? reason;
                          if (choice.$1 == '불참') {
                            reason = await _askAbsenceReason(context);
                            if (reason == null) return;
                          }
                          final saved = await ref
                              .read(lockerControllerProvider.notifier)
                              .vote(event.id, choice.$1, absenceReason: reason);
                          if (_attendanceUiRevisions[event.id] != revision) {
                            return;
                          }
                          if (saved) {
                            if (choice.$1 == '참석' &&
                                !active &&
                                context.mounted) {
                              unawaited(HapticFeedback.mediumImpact());
                              _showAttendanceCelebration(context);
                            }
                            await ref
                                .read(lockerControllerProvider.notifier)
                                .loadEventAttendance(event.id);
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
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
                      borderRadius: flush
                          ? BorderRadius.zero
                          : BorderRadius.circular(13),
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

  Future<String?> _askAbsenceReason(BuildContext context) => showDialog<String>(
    context: context,
    builder: (context) => const _AbsenceReasonDialog(),
  );
}

/// 밴드에서 실제로 가장 많이 쌓인 불참 사유 5종.
///
/// 선택지와 출결 통계의 분류가 어긋나지 않도록 목록은 여기서만 정의한다.
const absenceReasonPresets = <String>['가족 일정', '학업', '개인 선약', '여행', '부상·건강'];

/// 불참을 확정하려면 그대로 입력해야 하는 문구.
const absenceConfirmPhrase = '불참하겠습니다';

/// 직접 입력 선택지 라벨. 이 값 자체는 사유로 저장되지 않는다.
const _absenceCustomLabel = '직접 입력';

const _absenceReasonHints = <String, String>{
  '가족 일정': '본가 방문, 가족 여행, 가족 행사',
  '학업': '시험, 기말고사, 과제·프로젝트 마감, 세미나',
  '개인 선약': '미리 잡아 둔 약속',
  '여행': '개인 여행, 해외여행',
  '부상·건강': '부상, 감기, 고열 등',
  _absenceCustomLabel: '위 다섯 가지에 해당하지 않을 때만 사용해 주세요.',
};

/// 불참 사유를 고르고 확인 문구까지 입력해야 통과되는 다이얼로그.
class _AbsenceReasonDialog extends StatefulWidget {
  const _AbsenceReasonDialog();

  @override
  State<_AbsenceReasonDialog> createState() => _AbsenceReasonDialogState();
}

class _AbsenceReasonDialogState extends State<_AbsenceReasonDialog> {
  String? _selected;
  final _customController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// 저장될 사유 문자열. 선택지는 라벨 그대로, 직접 입력은 적은 내용을 쓴다.
  String? get _reason {
    final selected = _selected;
    if (selected == null) return null;
    if (selected != _absenceCustomLabel) return selected;
    final typed = _customController.text.trim();
    return typed.isEmpty ? null : typed;
  }

  bool get _confirmed =>
      _confirmController.text.trim() == absenceConfirmPhrase;

  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    final canSubmit = reason != null && _confirmed;
    return AlertDialog(
      title: const Text('불참 사유'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '불참은 팀 구성과 코트 배정에 바로 영향을 줍니다. 사유를 고르고 확인 문구까지 '
                '적게 한 건 한 번 더 신중하게 생각해 보시라는 뜻입니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: EncbaColors.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              for (final label in [...absenceReasonPresets, _absenceCustomLabel])
                _reasonTile(label),
              if (_selected == _absenceCustomLabel) ...[
                const SizedBox(height: 4),
                TextField(
                  controller: _customController,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '불참 사유를 직접 적어 주세요.',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                "확정하려면 아래에 '$absenceConfirmPhrase'를 그대로 입력해 주세요.",
                style: TextStyle(fontSize: 12, color: EncbaColors.ink),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _confirmController,
                maxLength: 20,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: absenceConfirmPhrase,
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: canSubmit ? () => Navigator.pop(context, reason) : null,
          child: const Text('불참 확정'),
        ),
      ],
    );
  }

  Widget _reasonTile(String label) {
    final active = _selected == label;
    final hint = _absenceReasonHints[label];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => setState(() => _selected = label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: active ? EncbaColors.absent.withValues(alpha: .08) : null,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: active ? EncbaColors.absent : EncbaColors.line,
            ),
          ),
          child: Row(
            children: [
              Icon(
                active
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: active ? EncbaColors.absent : EncbaColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: active ? EncbaColors.absent : EncbaColors.ink,
                      ),
                    ),
                    if (hint != null)
                      Text(
                        hint,
                        style: const TextStyle(
                          fontSize: 11,
                          color: EncbaColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showAttendanceCelebration(BuildContext context) {
  if (MediaQuery.disableAnimationsOf(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AttendanceCelebration(onComplete: entry.remove),
  );
  overlay.insert(entry);
}

class _AttendanceCelebration extends StatefulWidget {
  const _AttendanceCelebration({required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_AttendanceCelebration> createState() => _AttendanceCelebrationState();
}

class _AttendanceCelebrationState extends State<_AttendanceCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward().whenComplete(widget.onComplete);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      key: const ValueKey('attendance-celebration'),
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value;
            final scale = Curves.elasticOut.transform(
              math.min(progress / .62, 1),
            );
            final opacity = progress < .7 ? 1.0 : (1 - progress) / .3;
            return CustomPaint(
              painter: _AttendanceBurstPainter(progress),
              child: Center(
                child: Opacity(
                  opacity: opacity.clamp(0, 1),
                  child: Transform.scale(
                    scale: scale,
                    child: Semantics(
                      liveRegion: true,
                      label: '참석 확정',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF29A36A), Color(0xFF096540)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: EncbaColors.attending.withValues(
                                    alpha: .34,
                                  ),
                                  blurRadius: 30,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Material(
                            color: const Color(0xFF092E22),
                            borderRadius: BorderRadius.circular(999),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Text(
                                '참석 확정!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Jua',
                                  fontSize: 17,
                                  letterSpacing: .2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AttendanceBurstPainter extends CustomPainter {
  const _AttendanceBurstPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 38);
    final travel = Curves.easeOutCubic.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0);
    final ringPaint = Paint()
      ..color = EncbaColors.attending.withValues(alpha: fade * .32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * fade;
    canvas.drawCircle(center, 45 + 105 * travel, ringPaint);

    const colors = [Color(0xFF167A50), Color(0xFFFFB02E), Color(0xFFE96B2C)];
    for (var index = 0; index < 18; index++) {
      final angle = -math.pi / 2 + index * (2 * math.pi / 18);
      final distance = 48 + (92 + (index % 3) * 15) * travel;
      final particleCenter =
          center +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance);
      final paint = Paint()
        ..color = colors[index % colors.length].withValues(alpha: fade);
      final radius = (index.isEven ? 5.0 : 3.5) * fade;
      canvas.drawCircle(particleCenter, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AttendanceBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
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
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter oldDelegate) =>
      oldDelegate.color != color;
}

Color _kindColor(EventKind kind) => switch (kind) {
  EventKind.training => EncbaColors.snuBlue,
  EventKind.morning => const Color(0xFFD4A017),
  EventKind.freeOpen => const Color(0xFF2A7C67),
  EventKind.internal => EncbaColors.deepBlue,
  EventKind.pickup => EncbaColors.deepBlue,
  EventKind.ibDivision1 => const Color(0xFF4B2A75),
  EventKind.ibDivision2 || EventKind.ibFreshman => const Color(0xFF6D43A6),
  EventKind.scrimmage ||
  EventKind.threeWay ||
  EventKind.external => EncbaColors.absent,
  EventKind.operations => EncbaColors.late,
  EventKind.homecoming => const Color(0xFFB06C20),
};

({Color? color, Gradient? gradient, bool dark, bool split})
_uniformCardDecoration(LockerEvent event) {
  return (color: Colors.white, gradient: null, dark: false, split: false);
}

class _UniformCardForeground extends StatelessWidget {
  const _UniformCardForeground({required this.decoration, required this.child});

  final ({Color? color, Gradient? gradient, bool dark, bool split}) decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final foreground = decoration.dark ? Colors.white : EncbaColors.ink;
    Widget content = IconTheme.merge(
      data: IconThemeData(color: foreground),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: child,
      ),
    );
    if (!decoration.split) return content;
    content = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Colors.white, Colors.white, EncbaColors.ink, EncbaColors.ink],
        stops: [0, .46, .46, 1],
      ).createShader(bounds),
      child: content,
    );
    return content;
  }
}

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
  final reference = event.mapReference?.trim();
  final pastedUri = reference == null ? null : Uri.tryParse(reference);
  final isWebLink =
      pastedUri != null &&
      (pastedUri.scheme == 'https' || pastedUri.scheme == 'http');
  final target = reference != null && reference.isNotEmpty
      ? (isWebLink
            ? reference
            : 'https://map.naver.com/p/search/${Uri.encodeComponent(reference)}')
      : places[event.place] ??
            'https://map.naver.com/p/search/${Uri.encodeComponent(event.fullPlace)}';
  final uri = Uri.parse(target);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('네이버 지도를 열 수 없습니다.')));
  }
}

Future<void> _addCalendar(BuildContext context, LockerEvent event) async {
  final success = await addEventToCalendar(event);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(success ? '캘린더 추가 화면을 열었습니다.' : '이 기기에서는 캘린더를 열 수 없습니다.'),
      ),
    );
}
