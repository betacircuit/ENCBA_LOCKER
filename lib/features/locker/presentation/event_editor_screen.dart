part of 'event_screens.dart';

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
  late int _ibGameNumber;
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
    _deadlineCustomized = existing?.responseDeadlineOverride != null;
    _ibGameNumber = _inferIbGameNumber(_start);
    if (_isIbKind(_kind)) _applyIbGameSlot(_ibGameNumber);
    _preciseMinutes =
        _isIbKind(_kind) ||
        (existing != null &&
            (existing.start.minute != 0 || existing.end.minute != 0));
    _recurring = existing?.isRecurring ?? false;
    _responseEnabled = true;
    _starterIds = existing?.starterProfileIds.toSet() ?? <String>{};
    _responseDeadline =
        existing?.responseDeadline ??
        _start.subtract(
          _kind.isMatch ? const Duration(hours: 3) : const Duration(hours: 1),
        );
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
                      if (_isIbKind(_kind)) {
                        _applyIbGameSlot(_ibGameNumber);
                      }
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
                  if (_isIbKind(_kind))
                    DropdownButtonFormField<int>(
                      initialValue: _ibGameNumber,
                      decoration: const InputDecoration(labelText: '경기 시간 *'),
                      items: const [
                        DropdownMenuItem(
                          value: 1,
                          child: Text('1경기 · 13:00–14:00'),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text('2경기 · 14:10–15:10'),
                        ),
                        DropdownMenuItem(
                          value: 3,
                          child: Text('3경기 · 15:20–16:20'),
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _ibGameNumber = value!;
                        _applyIbGameSlot(value);
                      }),
                    )
                  else
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
                  if (!_isIbKind(_kind))
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

  static bool _isIbKind(EventKind kind) =>
      kind == EventKind.ibDivision1 || kind == EventKind.ibDivision2;

  int _inferIbGameNumber(DateTime start) =>
      switch ((start.hour, start.minute)) {
        (14, 10) => 2,
        (15, 20) => 3,
        _ => 1,
      };

  void _applyIbGameSlot(int gameNumber) {
    final slot = switch (gameNumber) {
      2 => (startHour: 14, startMinute: 10, endHour: 15, endMinute: 10),
      3 => (startHour: 15, startMinute: 20, endHour: 16, endMinute: 20),
      _ => (startHour: 13, startMinute: 0, endHour: 14, endMinute: 0),
    };
    _start = DateTime(
      _start.year,
      _start.month,
      _start.day,
      slot.startHour,
      slot.startMinute,
    );
    _end = DateTime(
      _start.year,
      _start.month,
      _start.day,
      slot.endHour,
      slot.endMinute,
    );
    _preciseMinutes = true;
    if (!_deadlineCustomized) {
      _responseDeadline = _start.subtract(const Duration(hours: 3));
    }
  }

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
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('응답 마감은 일정 시작 전이어야 합니다.')));
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
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('이미 같은 투표 항목이 있습니다.')));
      return;
    }
    setState(() {
      final index = _pollOptions.indexOf(option);
      if (index >= 0) _pollOptions[index] = edited;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isIbKind(_kind)) _applyIbGameSlot(_ibGameNumber);
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('종료 시간은 시작 시간보다 늦어야 합니다.')));
      return;
    }
    if (_responseDeadline.isAfter(_start)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('응답 마감은 일정 시작 전이어야 합니다.')));
      return;
    }
    if (_kind != EventKind.training &&
        _kind != EventKind.morning &&
        _kind != EventKind.freeOpen &&
        _uniforms.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('경기 유니폼 색을 하나 이상 선택해 주세요.')));
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
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
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
