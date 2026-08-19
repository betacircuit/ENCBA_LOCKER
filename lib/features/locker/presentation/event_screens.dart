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
    final states = ref.watch(
      lockerControllerProvider.select(
        (state) => (state.eventsState, state.operationsState),
      ),
    );
    final event = states.$1
        .plannerEventsWith(states.$2)
        .where((item) => item.id == widget.eventId)
        .firstOrNull;
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
    final eventsState = ref.watch(
      lockerControllerProvider.select((state) => state.eventsState),
    );
    final events = eventsState.events;
    final members = ref.watch(
      lockerControllerProvider.select((state) => state.membersState.members),
    );
    final event =
        events.where((item) => item.id == widget.initialEvent.id).firstOrNull ??
        widget.initialEvent;
    final responses =
        eventsState.eventAttendance[event.id] ?? const <AttendanceResponse>[];
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
              strategy:
                  eventsState.eventStrategies[event.id] ??
                  EventStrategy(eventId: event.id),
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
      ScaffoldMessenger.of(context).showSnackBar(
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

class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({super.key, this.eventId});

  final String? eventId;

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  @override
  Widget build(BuildContext context) {
    final eventId = widget.eventId;
    if (eventId == null) return const _EventEditorForm();
    return _EventResolver(
      eventId: eventId,
      builder: (event) => _EventEditorForm(existing: event),
    );
  }
}

class _EventEditorForm extends ConsumerStatefulWidget {
  const _EventEditorForm({this.existing});

  final LockerEvent? existing;

  @override
  ConsumerState<_EventEditorForm> createState() => _EventEditorFormState();
}

class _EventEditorFormState extends ConsumerState<_EventEditorForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _memo;
  late final TextEditingController _title;
  late final TextEditingController _opponentOne;
  late final TextEditingController _opponentTwo;
  late final TextEditingController _customPlace;
  late final TextEditingController _mapReference;
  late bool _hasCapacity;
  late double _capacity;
  late bool _hasObParticipants;
  late int _obParticipantCount;
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
  late Set<String> _starterIds;
  late DateTime _responseDeadline;
  bool _deadlineCustomized = false;
  bool _saving = false;

  static const _places = ['71동 종합체육관', '71-1동 신체육관', '900동 기숙사체육관'];
  static const _customPlaceOption = '직접 입력';
  static const _editableKinds = [
    EventKind.training,
    EventKind.morning,
    EventKind.freeOpen,
    EventKind.pickup,
    EventKind.ibDivision1,
    EventKind.ibDivision2,
    EventKind.scrimmage,
    EventKind.threeWay,
    EventKind.external,
  ];
  static const _ibDivisionOneTeams = [
    '서울대 농구부',
    '스티즈',
    '그래비티',
    '썬샷',
    '노바스',
    '호바스',
    '새턴',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _memo = TextEditingController(text: existing?.memo ?? '');
    _title = TextEditingController(
      text: existing == null || existing.title == existing.kind.label
          ? ''
          : existing.title,
    );
    _opponentOne = TextEditingController(
      text: existing?.opponents.elementAtOrNull(0) ?? '',
    );
    _opponentTwo = TextEditingController(
      text: existing?.opponents.elementAtOrNull(1) ?? '',
    );
    final knownPlace = existing == null || _places.contains(existing.place);
    _customPlace = TextEditingController(
      text: knownPlace ? '' : existing.place,
    );
    _mapReference = TextEditingController(text: existing?.mapReference ?? '');
    _hasCapacity = existing?.capacity != null;
    _capacity = (existing?.capacity ?? 20).clamp(2, 60).toDouble();
    _hasObParticipants = (existing?.obParticipantCount ?? 0) > 0;
    _obParticipantCount = (existing?.obParticipantCount ?? 1).clamp(1, 30);
    _kind = existing?.kind ?? EventKind.training;
    _place = existing?.place.trim().isNotEmpty == true
        ? (knownPlace ? existing!.place : _customPlaceOption)
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
    _starterIds = existing?.starterProfileIds.toSet() ?? <String>{};
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
    _title.dispose();
    _opponentOne.dispose();
    _opponentTwo.dispose();
    _customPlace.dispose();
    _mapReference.dispose();
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
    final placeOptions = [..._places, _customPlaceOption];
    final kindOptions = _editableKinds.contains(_kind)
        ? _editableKinds
        : [_kind, ..._editableKinds];
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(editing ? '일정 수정' : '새 일정')),
        body: Stack(
          children: [
            Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                    decoration: const InputDecoration(labelText: '일정 유형 *'),
                    items: kindOptions
                        .map(
                          (kind) => DropdownMenuItem(
                            value: kind,
                            child: Text(kind.label),
                          ),
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
                  TextFormField(
                    controller: _title,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: '제목 (선택)',
                      hintText: _kind.label,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: _team,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '공개 대상 *'),
                    items: const ['전체', 'ENCBA', 'BEN', '신입생']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
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
                        labelText: _kind == EventKind.threeWay
                            ? '상대팀 1 *'
                            : '상대팀 *',
                        hintText: 'IB 1부 팀 선택 또는 직접 입력',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 8),
                    _TeamSuggestionStrip(
                      teams: _ibDivisionOneTeams,
                      selected: {
                        _opponentOne.text.trim(),
                        if (_kind == EventKind.threeWay)
                          _opponentTwo.text.trim(),
                      }..remove(''),
                      maximumSelected: _kind == EventKind.threeWay ? 2 : 1,
                      onSelected: _selectSuggestedOpponent,
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
                    decoration: const InputDecoration(labelText: '공지 메모'),
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
                          _end = DateTime(
                            _end.year,
                            _end.month,
                            _end.day,
                            _end.hour,
                          );
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
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: _DateTimeButton(
                      label: '날짜',
                      value: _start,
                      dateOnly: true,
                      onTap: _pickEventDate,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _DateTimeButton(
                          label: '시작',
                          value: _start,
                          showMinutes: _preciseMinutes,
                          timeOnly: true,
                          onTap: () => _pickEventTime(true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DateTimeButton(
                          label: '종료',
                          value: _end,
                          showMinutes: _preciseMinutes,
                          timeOnly: true,
                          onTap: () => _pickEventTime(false),
                        ),
                      ),
                    ],
                  ),
                  if (_supportsStarters) ...[
                    const SizedBox(height: 18),
                    _StarterSelector(
                      members: ref.watch(
                        lockerControllerProvider.select(
                          (state) => state.membersState.members,
                        ),
                      ),
                      selectedIds: _starterIds,
                      onChanged: (ids) => setState(() => _starterIds = ids),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _place,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '장소 *'),
                    items: placeOptions
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _place = value!),
                  ),
                  if (_place == _customPlaceOption) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customPlace,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '장소 이름 *',
                        hintText: '예: 관악구민종합체육센터',
                      ),
                      validator: (value) => _place == _customPlaceOption
                          ? _required(value)
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _mapReference,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: '네이버 지도 링크 또는 주소',
                        hintText: '공유 링크나 도로명 주소를 붙여 넣어 주세요.',
                      ),
                    ),
                  ],
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
                    onEnabledChanged: (value) =>
                        setState(() => _hasCapacity = value),
                    onChanged: (value) => setState(() => _capacity = value),
                  ),
                  const SizedBox(height: 12),
                  _ObParticipantSelector(
                    enabled: _hasObParticipants,
                    count: _obParticipantCount,
                    onEnabledChanged: (value) =>
                        setState(() => _hasObParticipants = value),
                    onChanged: (value) =>
                        setState(() => _obParticipantCount = value),
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
                                : () => setState(
                                    () => _pollOptions.remove(option),
                                  ),
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
                          decoration: const InputDecoration(
                            hintText: '새 투표 항목',
                          ),
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
                    onChanged:
                        _kind == EventKind.training && widget.existing == null
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
            if (_saving)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: .88),
                  child: Center(
                    child: Semantics(
                      liveRegion: true,
                      label: '일정을 등록하는 중입니다',
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 42,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          SizedBox(height: 16),
                          Text(
                            '일정을 등록하는 중입니다',
                            style: TextStyle(
                              fontFamily: 'Jua',
                              fontSize: 20,
                              color: EncbaColors.navy,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            '잠시만 기다려 주세요.',
                            style: TextStyle(color: EncbaColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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

  bool get _supportsStarters => const {
    EventKind.ibDivision1,
    EventKind.ibDivision2,
    EventKind.external,
  }.contains(_kind);

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '필수 항목입니다.' : null;

  void _selectSuggestedOpponent(String team) {
    setState(() {
      final first = _opponentOne.text.trim();
      final second = _opponentTwo.text.trim();
      if (first == team) {
        _opponentOne.clear();
        return;
      }
      if (second == team) {
        _opponentTwo.clear();
        return;
      }
      if (_kind != EventKind.threeWay || first.isEmpty) {
        _opponentOne.text = team;
      } else if (second.isEmpty) {
        _opponentTwo.text = team;
      } else {
        _opponentTwo.text = team;
      }
    });
  }

  Future<void> _pickEventDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (!mounted || date == null) return;
    setState(() {
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        _start.hour,
        _start.minute,
      );
      _end = DateTime(date.year, date.month, date.day, _end.hour, _end.minute);
      if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 2));
      if (!_deadlineCustomized) {
        _responseDeadline = _start.subtract(
          _kind.isMatch ? const Duration(hours: 3) : const Duration(hours: 1),
        );
      }
    });
  }

  Future<void> _pickEventTime(bool start) async {
    final current = start ? _start : _end;
    final pickedTime = _preciseMinutes
        ? await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(current),
          )
        : await _pickHourOnly(current.hour);
    if (!mounted || pickedTime == null) return;
    final value = DateTime(
      _start.year,
      _start.month,
      _start.day,
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
      // 직접 입력한 제목이 없을 때만 일정 유형을 제목으로 사용한다.
      title: _title.text.trim().isEmpty ? _kind.label : _title.text.trim(),
      start: _start,
      end: _end,
      place: _place == _customPlaceOption ? _customPlace.text.trim() : _place,
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
      starterProfileIds: _supportsStarters ? _starterIds.toList() : const [],
      starterNames: _supportsStarters
          ? ref
                .read(lockerControllerProvider)
                .members
                .where((member) => _starterIds.contains(member.id))
                .map((member) => member.name)
                .toList()
          : const [],
      mapReference: _place == _customPlaceOption
          ? (_mapReference.text.trim().isEmpty
                ? null
                : _mapReference.text.trim())
          : null,
      obParticipantCount: _hasObParticipants ? _obParticipantCount : 0,
    );
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .saveEvent(event);
    if (!mounted) return;
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existing == null ? '일정이 등록되었습니다.' : '일정이 수정되었습니다.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
      final reason = ref.read(lockerControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason ?? '일정 저장에 실패했습니다. 입력값과 연결 상태를 확인해 주세요.'),
          action: SnackBarAction(label: '확인', onPressed: () {}),
        ),
      );
    }
  }

  Future<TimeOfDay?> _pickHourOnly(int initialHour) async {
    return showModalBottomSheet<TimeOfDay>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '시간 선택',
                style: TextStyle(
                  fontFamily: 'Jua',
                  fontSize: 24,
                  color: EncbaColors.navy,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                  childAspectRatio: 1.25,
                ),
                itemCount: 24,
                itemBuilder: (context, hour) => InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () =>
                      Navigator.pop(context, TimeOfDay(hour: hour, minute: 0)),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: hour == initialHour
                          ? EncbaColors.navy
                          : const Color(0xFFF1F4F8),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Text(
                        hour.toString().padLeft(2, '0'),
                        style: TextStyle(
                          color: hour == initialHour
                              ? Colors.white
                              : EncbaColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
  const _TeamSuggestionStrip({
    required this.teams,
    required this.selected,
    required this.maximumSelected,
    required this.onSelected,
  });
  final List<String> teams;
  final Set<String> selected;
  final int maximumSelected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: teams.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) => FilterChip(
        visualDensity: VisualDensity.compact,
        label: Text(teams[index]),
        selected: selected.contains(teams[index]),
        onSelected: (_) => onSelected(teams[index]),
      ),
    ),
  );
}

class _StarterSelector extends ConsumerWidget {
  const _StarterSelector({
    required this.members,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<MemberProfile> members;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNames = members
        .where((member) => selectedIds.contains(member.id))
        .map((member) => member.name)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('주전'),
        const SizedBox(height: 7),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _open(context, ref),
            icon: const Icon(Icons.groups_2_outlined),
            label: Text(
              selectedNames.isEmpty
                  ? '주전 선택'
                  : '${selectedNames.length}명 · ${selectedNames.join(', ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    var draft = {...selectedIds};
    // 이 화면을 멤버 목록이 아직 안 불러와진 채로 열었을 수 있다(로그인 직후
    // 곧장 일정 등록으로 들어온 경우). 비어 있으면 시트를 열기 전에 한 번
    // 다시 불러와서 "주전 선택"이 빈 목록으로 뜨는 걸 막는다.
    var source = members;
    if (source.isEmpty) {
      await ref.read(lockerControllerProvider.notifier).reload();
      if (!context.mounted) return;
      source = ref.read(lockerControllerProvider).membersState.members;
    }
    final available =
        source.where((member) => member.id != null && member.isActive).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .76,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '주전 선택',
                          style: TextStyle(
                            fontFamily: 'Jua',
                            fontSize: 24,
                            color: EncbaColors.navy,
                          ),
                        ),
                      ),
                      Text('${draft.length}/12명'),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: available.length,
                    itemBuilder: (context, index) {
                      final member = available[index];
                      final id = member.id!;
                      final checked = draft.contains(id);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(member.name),
                        subtitle: Text(
                          '${member.studentId} · ${member.position} #${member.jerseyNumber}',
                        ),
                        onChanged: (value) {
                          if (value == true && draft.length >= 12) return;
                          setSheetState(() {
                            value == true ? draft.add(id) : draft.remove(id);
                          });
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, draft),
                      child: const Text('주전 적용'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) onChanged(result);
  }
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
            Builder(
              builder: (context) {
                // 값 말풍선 위치를 직접 계산하던 예전 방식은 슬라이더 트랙
                // 안쪽 여백(양옆 라벨 폭만큼)을 셈에 넣지 않아, 값이 커질수록
                // 말풍선과 실제 손잡이 위치가 어긋났다. Slider의 내장
                // label(드래그 중 자동으로 손잡이 위를 따라가는 말풍선)을
                // 쓰면 이 계산 자체가 필요 없다.
                return Row(
                  children: [
                    const SizedBox(width: 24, child: Text('2')),
                    Expanded(
                      child: Slider(
                        value: value,
                        min: 2,
                        max: 20,
                        divisions: 18,
                        label: '${value.round()}명',
                        onChanged: onChanged,
                      ),
                    ),
                    const SizedBox(
                      width: 30,
                      child: Text('20', textAlign: TextAlign.right),
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

class _ObParticipantSelector extends StatelessWidget {
  const _ObParticipantSelector({
    required this.enabled,
    required this.count,
    required this.onEnabledChanged,
    required this.onChanged,
  });

  final bool enabled;
  final int count;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: EncbaColors.line),
      borderRadius: BorderRadius.circular(16),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        SwitchListTile.adaptive(
          value: enabled,
          title: const Text('OB 참여'),
          onChanged: onEnabledChanged,
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$count명',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Slider(
                  value: count.clamp(1, 15).toDouble(),
                  min: 1,
                  max: 15,
                  divisions: 14,
                  label: '$count명',
                  onChanged: (value) => onChanged(value.round()),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    required this.label,
    required this.value,
    required this.onTap,
    this.showMinutes = true,
    this.dateOnly = false,
    this.timeOnly = false,
  });
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  final bool showMinutes;
  final bool dateOnly;
  final bool timeOnly;

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
          dateOnly
              ? '${DateFormat('yyyy. M. d.').format(value)} (${weekday(value)})'
              : timeOnly
              ? (showMinutes
                    ? DateFormat('HH:mm').format(value)
                    : '${value.hour}시')
              : showMinutes
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
