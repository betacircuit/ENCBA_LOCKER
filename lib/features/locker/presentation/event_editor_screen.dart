part of 'locker_shell.dart';

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

  /// OB가 오긴 하는데 몇 명인지 밝히지 않을 때.
  late bool _obCountUnknown;
  late EventKind _kind;
  late String _place;

  /// 종합체육관은 A·B 코트를 함께 쓸 수 있어 여러 개를 고른다.
  late Set<String> _courts;
  late String _team;

  /// 공개 대상이 '직접 선택'일 때 이 일정을 볼 사람들.
  late Set<String> _audienceIds;
  late Set<String> _uniforms;
  late List<String> _pollOptions;
  final _pollOption = TextEditingController();
  late String _visibility;
  late DateTime _start;
  late DateTime _end;
  late int _ibGameNumber;
  late bool _responseEnabled;
  late Set<String> _starterIds;
  late DateTime _responseDeadline;
  bool _deadlineCustomized = false;
  bool _saving = false;

  static const _places = ['71동 종합체육관', '71-1동 신체육관', '900동 기숙사체육관'];
  static const _customPlaceOption = '직접 입력';
  static const _courtOptions = ['A코트', 'B코트'];
  static const _audienceDirect = '직접 선택';
  static const _teamOptions = ['전체', 'ENCBA', 'BEN', '신입생', _audienceDirect];

  /// 투표에서 뺄 수 없는 항목. 참석·불참은 어떤 일정에나 있어야 한다.
  static const _fixedPollOptions = ['참석', '불참'];
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
    _hasObParticipants = existing?.hasObParticipants ?? false;
    _obCountUnknown = existing?.obParticipantsUnknown ?? false;
    _obParticipantCount = (existing?.obParticipantCount ?? 1).clamp(1, 30);
    _kind = existing?.kind ?? EventKind.training;
    _place = existing?.place.trim().isNotEmpty == true
        ? (knownPlace ? existing!.place : _customPlaceOption)
        : _places.first;
    _courts =
        (existing?.court ?? '')
            .split('·')
            .map((value) => value.trim())
            .where(_courtOptions.contains)
            .toSet();
    if (_courts.isEmpty) _courts = {'A코트'};
    _team = switch (existing?.targetTeam) {
      'ENCBA 1부' => 'ENCBA',
      'ENCBA 2부' => 'BEN',
      final value? => value,
      _ => '전체',
    };
    _audienceIds = existing?.audienceProfileIds.toSet() ?? <String>{};
    _uniforms = existing?.uniformColors.toSet() ?? <String>{};
    _pollOptions = _withFixedPollOptions(
      existing?.pollOptions ?? const ['참석', '불참', '미정'],
    );
    _visibility = existing?.visibility ?? 'team';
    // 새 일정의 기본값은 내일 13:00:00~15:00:00이다. 대부분의 훈련이
    // 이 시간대라 손댈 일이 적고, 휠을 굴려 바로 바꿀 수 있다.
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _start =
        existing?.start ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 13);
    _end =
        existing?.end ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15);
    _deadlineCustomized = existing?.responseDeadlineOverride != null;
    _ibGameNumber = _inferIbGameNumber(_start);
    if (_isIbKind(_kind)) _applyIbGameSlot(_ibGameNumber);
    _responseEnabled = true;
    _starterIds = existing?.starterProfileIds.toSet() ?? <String>{};
    _responseDeadline =
        existing?.responseDeadline ??
        _start.subtract(LockerEvent.defaultResponseBuffer);
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
        appBar: AppBar(
          title: Text(editing ? '일정 수정' : '새 일정'),
          actions: [
            // 새 일정을 만들 때만 연다. 이미 있는 일정을 AI가 통째로
            // 덮어쓰면 무엇이 바뀌었는지 알기 어렵다.
            if (!editing)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _AiFillButton(
                  onPressed: _saving ? null : _composeWithAi,
                ),
              ),
          ],
        ),
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
                          LockerEvent.defaultResponseBuffer,
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
                  const _FormSectionTitle('시간'),
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
                    const SizedBox.shrink(),
                  if (!_isIbKind(_kind)) const SizedBox(height: 10),
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
                            secondsOnly: true,
                            onTap: () => _pickEventTime(true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DateTimeButton(
                            label: '종료',
                            value: _end,
                            secondsOnly: true,
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
                  const SizedBox(height: 24),
                  const _FormSectionTitle('장소'),
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
                    // 종합체육관은 두 코트를 함께 빌리는 날이 많아 중복 선택을
                    // 허용한다. 최소 한 곳은 골라야 한다.
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'A코트', label: Text('A코트')),
                        ButtonSegment(value: 'B코트', label: Text('B코트')),
                      ],
                      selected: _courts,
                      multiSelectionEnabled: true,
                      emptySelectionAllowed: false,
                      showSelectedIcon: false,
                      onSelectionChanged: (value) =>
                          setState(() => _courts = value),
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
                    countUnknown: _obCountUnknown,
                    onEnabledChanged: (value) =>
                        setState(() => _hasObParticipants = value),
                    onCountUnknownChanged: (value) =>
                        setState(() => _obCountUnknown = value),
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
                  const SizedBox(height: 24),
                  const _FormSectionTitle('참석 투표'),
                  const SizedBox(height: 6),
                  Text(
                    _hasCapacity
                        ? '인원 제한 ${_capacity.round()}명은 참석 항목에만 적용됩니다.'
                        : '참석·불참은 항상 들어갑니다. 필요하면 항목을 더 추가하세요.',
                    style: const TextStyle(
                      color: EncbaColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: _pollOptions.map((option) {
                      final fixed = _fixedPollOptions.contains(option);
                      return InputChip(
                        label: Text(
                          fixed && option == '참석' && _hasCapacity
                              ? '참석 (${_capacity.round()}명)'
                              : option,
                        ),
                        avatar: Icon(
                          fixed ? Icons.lock_outline_rounded : Icons.edit_outlined,
                          size: 15,
                        ),
                        onPressed: fixed ? null : () => _editPollOption(option),
                        onDeleted: fixed
                            ? null
                            : () => setState(() => _pollOptions.remove(option)),
                      );
                    }).toList(),
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
                  const SizedBox(height: 14),
                  _PollPreview(
                    options: _pollOptions,
                    attendanceLimit: _hasCapacity ? _capacity.round() : 0,
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
                              : '기본값 · 일정 시작 2시간 전',
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
                              LockerEvent.defaultResponseBuffer,
                            );
                          }),
                          child: const Text('기본값'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _FormSectionTitle('공개 대상'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _team,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '공개 대상 *'),
                    items: _teamOptions
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _team = value!),
                  ),
                  if (_team == _audienceDirect) ...[
                    const SizedBox(height: 10),
                    _AudiencePicker(
                      members: ref.watch(
                        lockerControllerProvider.select(
                          (state) => state.membersState.members,
                        ),
                      ),
                      selectedIds: _audienceIds,
                      onChanged: (ids) => setState(() => _audienceIds = ids),
                    ),
                  ],
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
                    if (widget.existing!.isCancelled)
                      // 취소된 일정도 내용은 고칠 수 있다. 여기서는 취소
                      // 자체를 되돌린다.
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _restoreEvent,
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: const Text('취소한 일정 되살리기'),
                      )
                    else
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: EncbaColors.absent,
                        ),
                        onPressed: _cancelEvent,
                        child: const Text('일정 취소'),
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

  /// 저장할 코트 문자열. 두 코트를 다 고르면 "A코트 · B코트"로 붙인다.
  String get _courtLabel =>
      (_courtOptions.where(_courts.contains).toList()).join(' · ');

  /// 참석·불참을 항상 앞에 두고 나머지를 뒤에 붙인다.
  List<String> _withFixedPollOptions(List<String> options) => [
    ..._fixedPollOptions,
    ...options.where((option) => !_fixedPollOptions.contains(option)),
  ];

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
    if (!_deadlineCustomized) {
      _responseDeadline = _start.subtract(LockerEvent.defaultResponseBuffer);
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
          LockerEvent.defaultResponseBuffer,
        );
      }
    });
  }

  /// 시작·종료 시각은 iOS 타이머처럼 시·분·초 휠을 굴려 고른다.
  Future<void> _pickEventTime(bool start) async {
    final current = start ? _start : _end;
    final picked = await showTimeWheelPicker(
      context: context,
      title: start ? '시작 시각' : '종료 시각',
      helperText: '시·분·초를 각각 드래그해서 맞춰 주세요.',
      initial: WheelTime.fromDateTime(current),
    );
    if (!mounted || picked == null) return;
    final value = picked.onDate(_start);
    setState(() {
      if (start) {
        _start = value;
        if (!_end.isAfter(value)) _end = value.add(const Duration(hours: 2));
        if (!_deadlineCustomized) {
          _responseDeadline = value.subtract(
            LockerEvent.defaultResponseBuffer,
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
    final picked = await showTimeWheelPicker(
      context: context,
      title: '투표 마감 시각',
      helperText: '시·분·초를 각각 드래그해서 맞춰 주세요.',
      initial: WheelTime.fromDateTime(_responseDeadline),
    );
    if (!mounted || picked == null) return;
    final value = picked.onDate(date);
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

  /// AI 채우기. 일정 하나면 이 화면의 입력값을 채우고, 여러 개면 한 번에
  /// 등록한다. "이번 학기 동안 매주 …" 같은 요청이 여기로 들어온다.
  Future<void> _composeWithAi() async {
    final drafts = await showAiEventComposer(
      context,
      academicLabel: _academicLabel(DateTime.now()),
    );
    if (drafts == null || drafts.isEmpty || !mounted) return;
    if (drafts.length == 1) {
      setState(() => _applyAiDraft(drafts.first));
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('AI가 채운 내용을 확인하고 등록해 주세요.')));
      return;
    }
    await _saveAiDrafts(drafts);
  }

  void _applyAiDraft(AiEventDraft draft) {
    _kind = draft.kind;
    _title.text = draft.title;
    _memo.text = draft.memo;
    _team = draft.targetTeam;
    _start = draft.start;
    _end = draft.end;
    if (_places.contains(draft.place)) {
      _place = draft.place;
    } else if (draft.place.isNotEmpty) {
      _place = _customPlaceOption;
      _customPlace.text = draft.place;
    }
    if (_isIbKind(_kind)) {
      _ibGameNumber = _inferIbGameNumber(_start);
      _applyIbGameSlot(_ibGameNumber);
    }
    if (_kind != EventKind.training &&
        _kind != EventKind.morning &&
        _kind != EventKind.freeOpen &&
        _uniforms.isEmpty) {
      _uniforms = {'검정', '흰색'};
    }
    if (!_deadlineCustomized) {
      _responseDeadline = _start.subtract(
        _kind.isMatch ? const Duration(hours: 3) : const Duration(hours: 1),
      );
    }
  }

  /// 여러 일정을 차례로 저장한다. 중간에 실패해도 몇 개가 들어갔는지
  /// 알려 줘야 관리자가 같은 일정을 두 번 만들지 않는다.
  Future<void> _saveAiDrafts(List<AiEventDraft> drafts) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('일정 ${drafts.length}개를 등록할까요?'),
        content: Text(
          '${drafts.first.start.month}.${drafts.first.start.day}부터 '
          '${drafts.last.start.month}.${drafts.last.start.day}까지 '
          '${drafts.length}개를 만듭니다. 등록 뒤에도 하나씩 수정하거나 취소할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('돌아가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('등록'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final user = ref.read(authControllerProvider).user;
    final notifier = ref.read(lockerControllerProvider.notifier);
    var saved = 0;
    for (final draft in drafts) {
      final ok = await notifier.saveEvent(_eventFromAiDraft(draft, user));
      if (!ok) break;
      saved++;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved == drafts.length
                ? '일정 $saved개를 등록했습니다.'
                : '일정 $saved개까지 등록하고 멈췄습니다. 남은 일정은 다시 시도해 주세요.',
          ),
        ),
      );
    if (saved > 0) Navigator.pop(context, true);
  }

  LockerEvent _eventFromAiDraft(AiEventDraft draft, UserProfile? user) {
    final isIb = _isIbKind(draft.kind);
    final needsUniform =
        draft.kind != EventKind.training &&
        draft.kind != EventKind.morning &&
        draft.kind != EventKind.freeOpen;
    final place = draft.place.trim().isEmpty
        ? _places.first
        : (isIb ? ibOperationVenue : draft.place.trim());
    return LockerEvent(
      id: 'event-${DateTime.now().microsecondsSinceEpoch}-${draft.start.millisecondsSinceEpoch}',
      title: draft.title.trim().isEmpty ? draft.kind.label : draft.title.trim(),
      start: draft.start,
      end: draft.end,
      place: place,
      court: place == _places.first ? 'A코트' : null,
      kind: draft.kind,
      memo: draft.memo,
      uniformColors: needsUniform ? const ['검정', '흰색'] : const [],
      targetTeam: draft.targetTeam,
      createdBy: '운영진 ${user?.name ?? ''}',
      updatedAt: '방금 전',
      responseEnabled: true,
      responseDeadlineOverride: draft.start.subtract(
        LockerEvent.defaultResponseBuffer,
      ),
      pollOptions: const ['참석', '불참', '미정'],
      visibility: 'team',
    );
  }

  /// 취소를 되돌린다. 응답 기록은 그대로 남아 있어 되살리면 이어서 쓴다.
  Future<void> _restoreEvent() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('취소를 되돌릴까요?'),
        content: const Text('부원들에게 다시 정상 일정으로 보이고, 참석 응답도 이어서 받습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('그대로 두기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('되살리기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final ok = await ref
        .read(lockerControllerProvider.notifier)
        .restoreEvent(existing.id);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(ok ? '일정을 되살렸습니다.' : '되살리지 못했습니다.')),
      );
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isIbKind(_kind)) _applyIbGameSlot(_ibGameNumber);
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('종료 시간은 시작 시간보다 늦어야 합니다.')),
        );
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
        ..showSnackBar(
          const SnackBar(content: Text('경기 유니폼 색을 하나 이상 선택해 주세요.')),
        );
      return;
    }
    if (_team == _audienceDirect && _audienceIds.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('공개 대상을 직접 선택하려면 부원을 한 명 이상 골라 주세요.')),
        );
      return;
    }
    if (_responseEnabled && _pollOptions.length < 2) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('저장하려면 투표 항목을 두 개 이상 추가해 주세요.')),
        );
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
      court: _place == _places.first ? _courtLabel : null,
      kind: _kind,
      memo: _memo.text.trim(),
      uniformColors: _uniforms.toList(),
      capacity: _hasCapacity ? _capacity.round() : null,
      attending: widget.existing?.attending ?? 0,
      targetTeam: _team,
      createdBy: widget.existing?.createdBy ?? '운영진 ${user?.name ?? ''}',
      updatedAt: '방금 전',
      // 매주 반복은 화면에서 뺐다. 이미 반복으로 만들어진 일정만 그 값을 지킨다.
      isRecurring: widget.existing?.isRecurring ?? false,
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
      obParticipantCount: _hasObParticipants && !_obCountUnknown
          ? _obParticipantCount
          : 0,
      obParticipantsUnknown: _hasObParticipants && _obCountUnknown,
      audienceProfileIds: _team == _audienceDirect
          ? _audienceIds.toList()
          : const [],
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

  Future<void> _cancelEvent() async {
    final reasonController = TextEditingController();
    var canSubmit = false;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('일정을 취소할까요?'),
          content: TextField(
            controller: reasonController,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            onChanged: (value) =>
                setDialogState(() => canSubmit = value.trim().isNotEmpty),
            decoration: const InputDecoration(
              labelText: '취소 사유 *',
              hintText: '예: 참석 인원이 부족해 일정이 취소되었습니다.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('돌아가기'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: EncbaColors.absent,
              ),
              onPressed: canSubmit
                  ? () => Navigator.pop(
                      dialogContext,
                      reasonController.text.trim(),
                    )
                  : null,
              child: const Text('일정 취소'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (reason == null) return;
    final cancelled = await ref
        .read(lockerControllerProvider.notifier)
        .cancelEvent(widget.existing!.id, reason);
    if (mounted && cancelled) {
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
    required this.countUnknown,
    required this.onEnabledChanged,
    required this.onCountUnknownChanged,
    required this.onChanged,
  });

  final bool enabled;
  final int count;

  /// OB가 오긴 하는데 몇 명인지 밝히지 않을 때.
  final bool countUnknown;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onCountUnknownChanged;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: EncbaColors.line),
      borderRadius: BorderRadius.circular(16),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      // 인원 제한 카드와 같은 여백을 써서 두 스위치가 같은 세로선에 선다.
      padding: const EdgeInsets.fromLTRB(14, 4, 10, 12),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            title: const Text('OB 참여'),
            subtitle: Text(
              !enabled
                  ? '참여 없음'
                  : countUnknown
                  ? '참여 · 인원 미정'
                  : '$count명 참여',
            ),
            onChanged: onEnabledChanged,
          ),
          if (enabled) ...[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: countUnknown,
              title: const Text('인원은 알리지 않기'),
              subtitle: const Text('몇 명 오는지 모를 때 켜 주세요.'),
              onChanged: onCountUnknownChanged,
            ),
            if (!countUnknown)
              Row(
                children: [
                  const SizedBox(width: 24, child: Text('1')),
                  Expanded(
                    child: Slider(
                      value: count.clamp(1, 15).toDouble(),
                      min: 1,
                      max: 15,
                      divisions: 14,
                      label: '$count명',
                      onChanged: (value) => onChanged(value.round()),
                    ),
                  ),
                  const SizedBox(
                    width: 30,
                    child: Text('15', textAlign: TextAlign.right),
                  ),
                ],
              ),
          ],
        ],
      ),
    ),
  );
}

class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    required this.label,
    required this.value,
    required this.onTap,
    this.dateOnly = false,
    this.secondsOnly = false,
  });
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  final bool dateOnly;

  /// 시·분·초를 모두 보여 준다. 휠로 고른 값을 그대로 확인할 수 있다.
  final bool secondsOnly;

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
          secondsOnly
              ? DateFormat('HH:mm:ss').format(value)
              : dateOnly
              ? '${DateFormat('yyyy. M. d.').format(value)} (${weekday(value)})'
              : DateFormat('M.d  HH:mm').format(value),
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

/// 투표가 부원 화면에서 어떻게 보이는지 미리 그려 준다. 등록하기 전에
/// 항목 이름과 정원이 말이 되는지 눈으로 확인할 수 있다.
class _PollPreview extends StatelessWidget {
  const _PollPreview({required this.options, required this.attendanceLimit});

  final List<String> options;

  /// 참석 항목에만 걸리는 정원. 0이면 제한 없음.
  final int attendanceLimit;

  Color _colorFor(String option) => switch (option) {
    '참석' => EncbaColors.attending,
    '불참' => EncbaColors.absent,
    '지각' => EncbaColors.late,
    '미정' => EncbaColors.undecided,
    _ => EncbaColors.deepBlue,
  };

  @override
  Widget build(BuildContext context) {
    // 눈대중용 가짜 숫자. 실제 응답이 아니라 "이렇게 보인다"는 예시다.
    final sample = <String, int>{
      for (final (index, option) in options.indexed)
        option: switch (index) {
          0 => 7,
          1 => 3,
          2 => 2,
          _ => 1,
        },
    };
    final total = sample.values.fold(0, (sum, value) => sum + value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EncbaColors.highlight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EncbaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.how_to_vote_outlined,
                size: 16,
                color: EncbaColors.snuBlue,
              ),
              const SizedBox(width: 6),
              const Text(
                '이렇게 보입니다',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const Spacer(),
              Text(
                '예시',
                style: TextStyle(
                  color: EncbaColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 부원이 누르는 버튼 줄.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: option == '참석'
                        ? _colorFor(option)
                        : _colorFor(option).withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: _colorFor(option).withValues(alpha: .35),
                    ),
                  ),
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: option == '참석'
                          ? Colors.white
                          : _colorFor(option),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // 집계 표.
          for (final option in options) ...[
            Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    option,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : (sample[option] ?? 0) / total,
                      minHeight: 7,
                      color: _colorFor(option),
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  child: Text(
                    option == '참석' && attendanceLimit > 0
                        ? '${sample[option]}/$attendanceLimit'
                        : '${sample[option]}명',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _colorFor(option),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (attendanceLimit > 0)
            Text(
              '참석이 $attendanceLimit명을 채우면 그 뒤로는 참석을 누를 수 없습니다.',
              style: const TextStyle(color: EncbaColors.muted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

/// 공개 대상을 '직접 선택'했을 때 쓰는 부원 고르기 카드.
class _AudiencePicker extends StatelessWidget {
  const _AudiencePicker({
    required this.members,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<MemberProfile> members;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedNames = members
        .where((member) => member.id != null && selectedIds.contains(member.id))
        .map((member) => member.name)
        .toList(growable: false);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: EncbaColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              selectedIds.isEmpty
                  ? '아직 고른 부원이 없습니다'
                  : '${selectedIds.length}명에게만 보입니다',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (selectedNames.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                selectedNames.join(', '),
                style: const TextStyle(
                  color: EncbaColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openPicker(context),
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('멤버 고르기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) =>
          _AudiencePickerSheet(members: members, initial: selectedIds),
    );
    if (picked != null) onChanged(picked);
  }
}

class _AudiencePickerSheet extends StatefulWidget {
  const _AudiencePickerSheet({required this.members, required this.initial});

  final List<MemberProfile> members;
  final Set<String> initial;

  @override
  State<_AudiencePickerSheet> createState() => _AudiencePickerSheetState();
}

class _AudiencePickerSheetState extends State<_AudiencePickerSheet> {
  late final Set<String> _selected = {...widget.initial};
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _query.text.trim();
    final candidates =
        widget.members
            .where((member) => member.id != null)
            .where(
              (member) =>
                  keyword.isEmpty ||
                  member.name.contains(keyword) ||
                  member.studentId.contains(keyword),
            )
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('공개할 부원', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '고른 사람에게만 이 일정이 보입니다. (${_selected.length}명 선택)',
              style: const TextStyle(color: EncbaColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '이름 또는 학번',
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: candidates.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        '찾는 부원이 없습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: EncbaColors.muted),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final member = candidates[index];
                        final id = member.id!;
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _selected.contains(id),
                          title: Text(member.name),
                          subtitle: Text(
                            '${member.teamLabel} · ${member.position} · '
                            '${member.studentId}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          }),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, _selected),
              child: Text('${_selected.length}명 선택 완료'),
            ),
          ],
        ),
      ),
    );
  }
}
