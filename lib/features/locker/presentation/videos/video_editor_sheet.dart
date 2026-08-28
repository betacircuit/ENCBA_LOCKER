part of '../locker_shell.dart';

void _showVideoEditor(
  BuildContext context,
  WidgetRef ref,
  String category, {
  VideoItem? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _VideoEditorSheet(category: category, existing: existing),
);

class _VideoEditorSheet extends ConsumerStatefulWidget {
  const _VideoEditorSheet({required this.category, this.existing});
  final String category;
  final VideoItem? existing;

  @override
  ConsumerState<_VideoEditorSheet> createState() => _VideoEditorSheetState();
}

/// 편집 중인 링크 한 줄. [quarterNumber]가 null이면 쿼터 미정이다.
class _VideoLinkField {
  _VideoLinkField({required this.quarterNumber, required this.controller});

  int? quarterNumber;
  final TextEditingController controller;
}

class _VideoEditorSheetState extends ConsumerState<_VideoEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _title = TextEditingController();
  late final List<_VideoLinkField> _links;
  DateTime? _recordedOn;
  late String _audienceType;
  late Set<String> _audienceValues;
  late Set<String> _reviewPlayerIds;
  bool _saving = false;
  String? _saveError;

  static const _maxQuarter = 6;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _url.text = existing?.url ?? '';
    _title.text = existing?.title ?? '';
    final saved = sortedVideoLinks(existing?.links ?? const []);
    _links = saved.isEmpty
        ? [
            for (var quarter = 1; quarter <= 4; quarter++)
              _VideoLinkField(
                quarterNumber: quarter,
                controller: TextEditingController(),
              ),
          ]
        : [
            for (final link in saved)
              _VideoLinkField(
                quarterNumber: link.quarterNumber,
                controller: TextEditingController(text: link.url),
              ),
          ];
    _recordedOn = existing?.recordedOn;
    _audienceType = existing?.audienceType ?? 'all';
    _audienceValues = existing?.audienceValues.toSet() ?? <String>{};
    _reviewPlayerIds =
        existing?.reviewPlayers.map((member) => member.directoryId).toSet() ??
        <String>{};
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    for (final field in _links) {
      field.controller.dispose();
    }
    super.dispose();
  }

  /// 아직 쓰지 않은 가장 작은 쿼터 번호를 붙여 한 줄 늘린다.
  void _addQuarterField() {
    final used = _links
        .map((field) => field.quarterNumber)
        .whereType<int>()
        .toSet();
    final next = [
      for (var quarter = 1; quarter <= _maxQuarter; quarter++)
        if (!used.contains(quarter)) quarter,
    ].firstOrNull;
    if (next == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('쿼터는 $_maxQuarter개까지 추가할 수 있습니다.')),
        );
      return;
    }
    setState(
      () => _links.add(
        _VideoLinkField(
          quarterNumber: next,
          controller: TextEditingController(),
        ),
      ),
    );
  }

  void _addUndecidedField() => setState(
    () => _links.add(
      _VideoLinkField(quarterNumber: null, controller: TextEditingController()),
    ),
  );

  void _removeField(int index) {
    final removed = _links.removeAt(index);
    setState(() {});
    removed.controller.dispose();
  }

  List<VideoLink> _collectedLinks() => [
    for (final field in _links)
      if (field.controller.text.trim().isNotEmpty)
        VideoLink(
          url: field.controller.text.trim(),
          quarterNumber: field.quarterNumber,
        ),
  ];

  Future<void> _pickRecordedOn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordedOn ?? now,
      firstDate: DateTime(1977),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: '경기 날짜 선택',
    );
    if (picked == null || !mounted) return;
    setState(() => _recordedOn = picked);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final isReview = widget.category == '복기';
    final isHighlight = widget.category == '하이라이트';
    final links = _collectedLinks();
    final rawSourceUrl = isReview
        ? (sortedVideoLinks(links).firstOrNull?.url ?? '')
        : _url.text.trim();
    final youtubeId = _youtubeIdFrom(rawSourceUrl);
    final isInstagram = isHighlight && _isInstagramReel(rawSourceUrl);
    if (youtubeId == null && !isInstagram) {
      setState(() => _saving = false);
      return;
    }
    final sourceUrl = isInstagram
        ? (_normalizedInstagramUri(rawSourceUrl)?.toString() ?? rawSourceUrl)
        : rawSourceUrl;
    if (widget.category == '공유' &&
        (_audienceType == 'position' || _audienceType == 'student_year') &&
        _audienceValues.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('추천 대상을 하나 이상 선택해 주세요.')));
      setState(() => _saving = false);
      return;
    }
    if (isReview) {
      final filled = links
          .map((link) => link.quarterNumber)
          .whereType<int>()
          .toSet();
      // 1쿼터부터 채워 온 자리 가운데 빠진 곳만 짚어 준다. 5쿼터 이후나
      // 쿼터 미정 링크는 원래 비어 있는 게 정상이라 묻지 않는다.
      final blankQuarters = <int>[
        for (var quarter = 1; quarter <= 4; quarter++)
          if (!filled.contains(quarter)) quarter,
      ];
      if (blankQuarters.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('빈 쿼터를 확인해 주세요'),
            content: Text(
              '${blankQuarters.map((quarter) => '$quarter쿼터').join(', ')} 영상이 비어 있습니다. 이대로 올릴까요?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('돌아가기'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('비운 채 올리기'),
              ),
            ],
          ),
        );
        if (confirmed != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
    }
    final user = ref.read(authControllerProvider).user;
    final members = ref.read(lockerControllerProvider).members;
    final reviewPlayerById = <String, VideoTaggedMember>{
      for (final member in widget.existing?.reviewPlayers ?? const [])
        member.directoryId: member,
      for (final member in members)
        if (member.id != null) member.id!: _taggedMember(member),
    };
    final reviewPlayers =
        _reviewPlayerIds
            .map((id) => reviewPlayerById[id])
            .whereType<VideoTaggedMember>()
            .toList(growable: false)
          ..sort(compareTaggedMembers);
    final now = DateTime.now();
    final video = VideoItem(
      id: widget.existing?.id ?? 'video-${now.microsecondsSinceEpoch}',
      title: _title.text.trim(),
      // 릴스에는 재생 시간이 없다. 예전에 저장된 값만 그대로 지킨다.
      durationLabel: isReview ? '' : (widget.existing?.durationLabel ?? ''),
      category: widget.category,
      url: sourceUrl,
      youtubeId: youtubeId ?? '',
      sourceType: isInstagram ? 'instagram' : 'youtube',
      links: isReview ? sortedVideoLinks(links) : const [],
      recordedOn: widget.category == '공유' ? null : _recordedOn,
      uploadedAt: widget.existing?.uploadedAt ?? now,
      uploader: widget.existing?.uploader ?? user?.name ?? 'ENCBA',
      accent: EncbaColors.snuBlue.toARGB32(),
      likeCount: widget.existing?.likeCount ?? 0,
      audienceType: widget.category == '공유' ? _audienceType : 'all',
      audienceValues: widget.category == '공유'
          ? _audienceValues.toList()
          : const [],
      reviewPlayers: isReview ? reviewPlayers : const [],
    );
    final notifier = ref.read(lockerControllerProvider.notifier);
    final saved = widget.existing == null
        ? await notifier.addVideo(video)
        : await notifier.updateVideo(video);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existing == null ? '영상을 등록했습니다.' : '영상을 수정했습니다.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _saving = false;
      _saveError = '저장하지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isReview = widget.category == '복기';
    final sourceUrl = isReview
        ? (sortedVideoLinks(_collectedLinks()).firstOrNull?.url ?? '')
        : _url.text.trim();
    final previewYoutubeId = _youtubeIdFrom(sourceUrl);
    final previewInstagram =
        widget.category == '하이라이트' && _isInstagramReel(sourceUrl);
    final availableReviewPlayerById = <String, VideoTaggedMember>{
      for (final member in widget.existing?.reviewPlayers ?? const [])
        member.directoryId: member,
      for (final member in ref.watch(
        lockerControllerProvider.select((state) => state.membersState.members),
      ))
        if (member.id != null && member.isActiveMember)
          member.id!: _taggedMember(member),
    };
    final availableReviewPlayers = availableReviewPlayerById.values.toList()
      ..sort(compareTaggedMembers);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.category == '공유'
                      ? '농구 영상 공유'
                      : '${widget.category} 추가',
                  style: const TextStyle(
                    fontFamily: 'Jua',
                    fontSize: 24,
                    color: EncbaColors.navy,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '제목'),
                  validator: (value) =>
                      (value?.trim().isEmpty ?? true) ? '제목을 입력해 주세요.' : null,
                ),
                const SizedBox(height: 12),
                if (isReview) ...[
                  const Text('쿼터별 YouTube 링크'),
                  const SizedBox(height: 4),
                  const Text(
                    '쿼터를 모르는 영상은 "쿼터 미정"으로 올려도 됩니다.',
                    style: TextStyle(color: EncbaColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  for (final (index, field) in _links.indexed) ...[
                    _VideoLinkRow(
                      field: field,
                      maxQuarter: _maxQuarter,
                      takenQuarters: {
                        for (final other in _links)
                          if (!identical(other, field) &&
                              other.quarterNumber != null)
                            other.quarterNumber!,
                      },
                      onQuarterChanged: (quarter) =>
                          setState(() => field.quarterNumber = quarter),
                      onChanged: () => setState(() {}),
                      onRemove: _links.length == 1
                          ? null
                          : () => _removeField(index),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) {
                          return _collectedLinks().isEmpty
                              ? '최소 한 개의 링크가 필요합니다.'
                              : null;
                        }
                        return _youtubeIdFrom(text) == null
                            ? '올바른 YouTube 링크를 입력해 주세요.'
                            : null;
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _addQuarterField,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('쿼터 추가'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _addUndecidedField,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('쿼터 미정'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    onChanged: (value) {
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: widget.category == '하이라이트'
                          ? 'YouTube 또는 Instagram Reel 링크'
                          : 'YouTube 링크',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      final validYoutube = _youtubeIdFrom(text) != null;
                      final validInstagram =
                          widget.category == '하이라이트' && _isInstagramReel(text);
                      return validYoutube || validInstagram
                          ? null
                          : '올바른 영상 링크를 입력해 주세요.';
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                if (previewYoutubeId != null || previewInstagram) ...[
                  _VideoLinkPreview(
                    youtubeId: previewYoutubeId,
                    sourceUrl: sourceUrl,
                    sourceType: previewInstagram ? 'instagram' : 'youtube',
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.category != '공유') ...[
                  _RecordedDateField(
                    value: _recordedOn,
                    onPick: _pickRecordedOn,
                    onClear: _recordedOn == null
                        ? null
                        : () => setState(() => _recordedOn = null),
                  ),
                  const SizedBox(height: 12),
                ],
                if (isReview) ...[
                  _MemberChecklistButton(
                    label: '출전 선수',
                    members: availableReviewPlayers,
                    selectedIds: _reviewPlayerIds,
                    onChanged: (value) => setState(() {
                      _reviewPlayerIds = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.category == '공유') ...[
                  const SizedBox(height: 16),
                  _VideoAudienceSelector(
                    type: _audienceType,
                    values: _audienceValues,
                    onChanged: (type, values) => setState(() {
                      _audienceType = type;
                      _audienceValues = values;
                    }),
                  ),
                ],
                if (_saveError case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: EncbaColors.absent),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.existing == null ? '등록' : '저장'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 링크 한 줄. 왼쪽에서 쿼터를 고르고 오른쪽에 주소를 넣는다.
class _VideoLinkRow extends StatelessWidget {
  const _VideoLinkRow({
    required this.field,
    required this.maxQuarter,
    required this.takenQuarters,
    required this.onQuarterChanged,
    required this.onChanged,
    required this.onRemove,
    required this.validator,
  });

  final _VideoLinkField field;
  final int maxQuarter;
  final Set<int> takenQuarters;
  final ValueChanged<int?> onQuarterChanged;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 쿼터는 직접 숫자로 적는다. 목록에서 고르게 했더니 길게 늘어져
      // 화면을 덮었고, 손으로 치는 편이 빨랐다. 비워 두면 '미정'이다.
      SizedBox(
        width: 92,
        child: TextFormField(
          key: ObjectKey(field),
          initialValue: field.quarterNumber?.toString() ?? '',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 1,
          decoration: const InputDecoration(
            labelText: '쿼터',
            hintText: '미정',
            counterText: '',
          ),
          onChanged: (value) {
            final quarter = int.tryParse(value.trim());
            onQuarterChanged(
              quarter != null && quarter >= 1 && quarter <= maxQuarter
                  ? quarter
                  : null,
            );
          },
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return null;
            final quarter = int.tryParse(text);
            if (quarter == null || quarter < 1 || quarter > maxQuarter) {
              return '1~$maxQuarter';
            }
            if (quarter != field.quarterNumber &&
                takenQuarters.contains(quarter)) {
              return '중복';
            }
            return null;
          },
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextFormField(
          controller: field.controller,
          keyboardType: TextInputType.url,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(labelText: 'YouTube 링크'),
          validator: validator,
        ),
      ),
      IconButton(
        tooltip: '이 링크 지우기',
        onPressed: onRemove,
        icon: const Icon(Icons.remove_circle_outline_rounded),
      ),
    ],
  );
}

/// 경기가 열린 날. 비워 두면 업로드 날짜만 보인다.
class _RecordedDateField extends StatelessWidget {
  const _RecordedDateField({
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: '경기 날짜',
      suffixIcon: onClear == null
          ? const Icon(Icons.event_outlined)
          : IconButton(
              tooltip: '날짜 지우기',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
    ),
    child: InkWell(
      onTap: onPick,
      child: Text(
        value == null
            ? '날짜 선택 (선택 사항)'
            : '${DateFormat('yyyy년 M월 d일').format(value!)} ${weekday(value!)}',
        style: TextStyle(
          color: value == null ? EncbaColors.muted : EncbaColors.ink,
        ),
      ),
    ),
  );
}

VideoTaggedMember _taggedMember(MemberProfile member) => VideoTaggedMember(
  directoryId: member.id!,
  name: member.name,
  studentYear: int.tryParse(member.studentId.replaceAll(RegExp(r'[^0-9]'), '')),
  jerseyNumber: member.jerseyNumber,
);

class _VideoAudienceSelector extends StatelessWidget {
  const _VideoAudienceSelector({
    required this.type,
    required this.values,
    required this.onChanged,
  });

  final String type;
  final Set<String> values;
  final void Function(String type, Set<String> values) onChanged;

  static const _types = <(String, String)>[
    ('all', '전체'),
    ('position', '포지션'),
    ('freshman', '신입생'),
    ('student_year', '학번'),
  ];
  static const _positions = ['PG', 'SG', 'SF', 'PF', 'C', '미정'];

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year % 100;
    final studentYears = [
      for (var year = currentYear - 8; year <= currentYear; year++)
        year.toString().padLeft(2, '0'),
    ].reversed.toList();
    final choices = type == 'position'
        ? _positions
        : type == 'student_year'
        ? studentYears
        : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('추천 대상', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
          '선택한 부원에게만 이 공유 영상이 보입니다.',
          style: TextStyle(color: EncbaColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: _types
              .map(
                (item) => ChoiceChip(
                  label: Text(item.$2),
                  selected: type == item.$1,
                  onSelected: (_) => onChanged(item.$1, <String>{}),
                ),
              )
              .toList(),
        ),
        if (choices.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: choices
                .map(
                  (value) => FilterChip(
                    label: Text(type == 'student_year' ? '$value학번' : value),
                    selected: values.contains(value),
                    onSelected: (selected) {
                      final next = {...values};
                      selected ? next.add(value) : next.remove(value);
                      onChanged(type, next);
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _VideoLinkPreview extends StatelessWidget {
  const _VideoLinkPreview({
    required this.youtubeId,
    required this.sourceUrl,
    required this.sourceType,
  });

  final String? youtubeId;
  final String sourceUrl;
  final String sourceType;

  @override
  Widget build(BuildContext context) {
    final thumbnail = _videoThumbnailUrl(
      youtubeId: youtubeId ?? '',
      sourceUrl: sourceUrl,
    );
    final asset = _instagramThumbnailAsset(sourceUrl);
    final reelUrl = sourceType == 'instagram'
        ? _instagramThumbnailUrl(sourceUrl)
        : null;
    if (thumbnail == null && asset == null && reelUrl == null) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: asset != null
            ? Image.asset(
                asset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              )
            : reelUrl != null
            ? _InstagramThumbnailImage(
                url: reelUrl,
                fallbackBuilder: () => const ColoredBox(
                  color: EncbaColors.line,
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: EncbaColors.muted,
                    ),
                  ),
                ),
              )
            : _YoutubeThumbnailImage(
                youtubeId: youtubeId ?? '',
                sourceUrl: sourceUrl,
                fallbackBuilder: () => const ColoredBox(
                  color: EncbaColors.line,
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: EncbaColors.muted,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

const _bundledReelShortcodes = {
  'Db2nVhDz4Fq',
  'DajgzpRTc4e',
  'DZDMprWogCr',
  'DXPE0fsEwcm',
  'DTnGCB7E50t',
};

/// 사용자가 "https://" 없이 `instagram.com/reel/...`만 붙여넣어도 인식하도록
/// 스킴을 보정한다. 스킴 없이 파싱하면 전체 문자열이 하나의 상대 경로로
/// 취급돼 host가 비어 있어 정상적인 링크도 Reel로 인식되지 않았다.
Uri? _normalizedInstagramUri(String input) {
  final trimmed = input.trim();
  final withScheme =
      RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)
      ? trimmed
      : 'https://$trimmed';
  return Uri.tryParse(withScheme);
}

String? _instagramShortcode(String input) {
  final uri = _normalizedInstagramUri(input);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host != 'instagram.com' &&
      host != 'www.instagram.com' &&
      host != 'm.instagram.com') {
    return null;
  }
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  final markerIndex = segments.indexWhere(
    (part) => const {'reel', 'reels', 'p'}.contains(part.toLowerCase()),
  );
  if (markerIndex < 0 || markerIndex + 1 >= segments.length) return null;
  final shortcode = segments[markerIndex + 1];
  return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(shortcode) ? shortcode : null;
}

bool _isInstagramReel(String input) {
  final uri = _normalizedInstagramUri(input);
  if (uri == null || _instagramShortcode(input) == null) return false;
  return uri.pathSegments.any(
    (part) => const {'reel', 'reels'}.contains(part.toLowerCase()),
  );
}

bool _canCreateVideoCategory(UserProfile user, String category) {
  if (category == '하이라이트') return user.canManageHighlights;
  return category == '복기' || category == '공유';
}

bool _canManageVideo(UserProfile? user, VideoItem video) {
  if (user == null) return false;
  if (video.category == '하이라이트') {
    return user.canManageHighlights || user.canAdminister;
  }
  return video.category == '복기' || video.category == '공유';
}
