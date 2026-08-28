part of '../locker_shell.dart';

/// AI 채우기 시트. 프롬프트 한 줄을 받아 초안을 만들고, AI가 정하지 못한
/// 항목만 골라 되물은 뒤 결과를 돌려준다. 되묻는 항목은 비워 둔 채
/// 넘어갈 수 있다 - 그때는 기존 기본값이 그대로 쓰인다.
///
/// API 키는 `ai-compose` 엣지 함수의 환경변수에만 있고 앱에는 내려오지 않는다.

/// 화면 오른쪽 위에 앉는 파란 "AI로 채우기" 버튼.
class _AiFillButton extends StatelessWidget {
  const _AiFillButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: EncbaColors.snuBlue,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      // 버튼 글씨는 앱의 표시용 글꼴(Jua)로 맞춘다. 기본 라벨 스타일을
      // 그대로 쓰면 시스템 글꼴로 새어 나가 헤더와 따로 놀았다.
      textStyle: const TextStyle(
        fontFamily: 'Jua',
        fontFamilyFallback: encbaFontFallback,
        fontSize: 14,
        letterSpacing: .2,
      ),
    ),
    // 이모지는 컬러 폰트라 흰색으로 못 칠한다. 같은 모양의 아이콘을 써야
    // 파란 버튼 위에서 흰색으로 보인다.
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
        SizedBox(width: 6),
        Text('AI로 채우기'),
      ],
    ),
  );
}

Future<List<AiEventDraft>?> showAiEventComposer(
  BuildContext context, {
  required String academicLabel,
}) => showModalBottomSheet<List<AiEventDraft>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
    ),
    child: _AiEventComposerSheet(academicLabel: academicLabel),
  ),
);

Future<AiAnnouncementDraft?> showAiAnnouncementComposer(BuildContext context) =>
    showModalBottomSheet<AiAnnouncementDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: const _AiAnnouncementComposerSheet(),
      ),
    );

/// 프롬프트 입력 칸. 두 시트가 같은 모양을 쓴다.
class _AiPromptField extends StatelessWidget {
  const _AiPromptField({
    required this.controller,
    required this.hintText,
    required this.enabled,
  });

  final TextEditingController controller;
  final String hintText;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    minLines: 3,
    maxLines: 6,
    maxLength: 2000,
    keyboardType: TextInputType.multiline,
    decoration: InputDecoration(
      labelText: '무엇을 채울까요?',
      alignLabelWithHint: true,
      hintText: hintText,
    ),
  );
}

class _AiErrorText extends StatelessWidget {
  const _AiErrorText({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      message,
      style: const TextStyle(color: EncbaColors.absent, fontSize: 13),
    ),
  );
}

// ---------------------------------------------------------------------------
// 일정
// ---------------------------------------------------------------------------

class _AiEventComposerSheet extends StatefulWidget {
  const _AiEventComposerSheet({required this.academicLabel});

  final String academicLabel;

  @override
  State<_AiEventComposerSheet> createState() => _AiEventComposerSheetState();
}

class _AiEventComposerSheetState extends State<_AiEventComposerSheet> {
  final _prompt = TextEditingController();
  final _answers = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;
  AiEventPlan? _plan;
  late Set<int> _selected = <int>{};

  @override
  void dispose() {
    _prompt.dispose();
    for (final controller in _answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.length < 2 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await AiComposeService().composeEvents(
        prompt: prompt,
        context: {'academicTerm': widget.academicLabel},
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _selected = {for (var index = 0; index < plan.events.length; index++) index};
        _busy = false;
        for (final question in plan.questions) {
          _answers.putIfAbsent(question.field, TextEditingController.new);
        }
      });
    } on AiComposeException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  /// 되물은 값이 채워졌으면 초안에 덮어쓴다. 비워 뒀으면 AI가 준 값을
  /// 그대로 쓴다("그냥 안 채우고 넘어가기").
  List<AiEventDraft> _applyAnswers(List<AiEventDraft> drafts) {
    String answer(String field) => _answers[field]?.text.trim() ?? '';
    return [
      for (final draft in drafts)
        AiEventDraft(
          kind: draft.kind,
          title: answer('title').isEmpty ? draft.title : answer('title'),
          start: draft.start,
          end: draft.end,
          place: answer('place').isEmpty ? draft.place : answer('place'),
          targetTeam: const ['전체', 'ENCBA', 'BEN', '신입생'].contains(
            answer('targetTeam'),
          )
              ? answer('targetTeam')
              : draft.targetTeam,
          memo: answer('memo').isEmpty ? draft.memo : answer('memo'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: EncbaColors.snuBlue,
                ),
                const SizedBox(width: 8),
                Text('AI로 일정 채우기', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '대충 편하게 말씀해주세요~',
              style: TextStyle(
                color: EncbaColors.muted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            _AiPromptField(
              controller: _prompt,
              hintText: '이번 학기 동안 매주 화요일 8시부터 10시까지 종합체육관에서 훈련이요',
              enabled: !_busy,
            ),
            if (_error case final String message) _AiErrorText(message: message),
            if (_busy) ...[
              const SizedBox(height: 14),
              const _AiProgressBar(label: 'AI가 일정을 만들고 있습니다'),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(
                _busy
                    ? '만드는 중…'
                    : plan == null
                    ? '일정 만들기'
                    : '다시 만들기',
              ),
            ),
            if (plan != null) ...[
              const SizedBox(height: 18),
              if (plan.summary.isNotEmpty)
                Text(
                  plan.summary,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 10),
              if (plan.questions.isNotEmpty) ...[
                _AiQuestionsCard(
                  questions: plan.questions,
                  controllers: _answers,
                  optionsFor: _eventFieldOptions,
                ),
                const SizedBox(height: 12),
              ],
              Text(
                '만든 일정 ${plan.events.length}개 · 선택 ${_selected.length}개',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: plan.events.length,
                  itemBuilder: (context, index) {
                    final draft = plan.events[index];
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _selected.contains(index),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(index);
                        } else {
                          _selected.remove(index);
                        }
                      }),
                      title: Text(
                        draft.title.isEmpty ? draft.kind.label : draft.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${draft.start.month}.${draft.start.day} '
                        '${_hhmm(draft.start)}–${_hhmm(draft.end)} · '
                        '${draft.place.isEmpty ? '장소 미정' : draft.place}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        _applyAnswers([
                          for (final index in _selected.toList()..sort())
                            plan.events[index],
                        ]),
                      ),
                child: Text(
                  _selected.length == 1
                      ? '이 일정으로 채우기'
                      : '${_selected.length}개 일정 등록하기',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<String>? _eventFieldOptions(String field) => switch (field) {
  'targetTeam' => const ['전체', 'ENCBA', 'BEN', '신입생'],
  'place' => const ['71동 종합체육관', '71-1동 신체육관', '900동 기숙사체육관'],
  _ => null,
};

String _hhmm(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

/// AI가 정하지 못해 되묻는 항목들. 비워 두면 그대로 넘어간다.
class _AiQuestionsCard extends StatelessWidget {
  const _AiQuestionsCard({
    required this.questions,
    required this.controllers,
    required this.optionsFor,
  });

  final List<AiFollowUpQuestion> questions;
  final Map<String, TextEditingController> controllers;
  final List<String>? Function(String field) optionsFor;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'AI가 확인하고 싶은 것',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          const Text(
            '비워 두고 넘어가도 됩니다. 그러면 기본값이 그대로 쓰입니다.',
            style: TextStyle(color: EncbaColors.muted, fontSize: 12),
          ),
          for (final question in questions) ...[
            const SizedBox(height: 12),
            Text(question.question, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            if (optionsFor(question.field) case final List<String> options)
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final option in options)
                    _AiAnswerChip(
                      label: option,
                      controller: controllers[question.field],
                    ),
                ],
              )
            else
              TextField(
                controller: controllers[question.field],
                decoration: const InputDecoration(hintText: '비워 두면 넘어갑니다'),
              ),
          ],
        ],
      ),
    ),
  );
}

class _AiAnswerChip extends StatefulWidget {
  const _AiAnswerChip({required this.label, required this.controller});

  final String label;
  final TextEditingController? controller;

  @override
  State<_AiAnswerChip> createState() => _AiAnswerChipState();
}

class _AiAnswerChipState extends State<_AiAnswerChip> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final selected = controller?.text == widget.label;
    return ChoiceChip(
      label: Text(widget.label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: controller == null
          ? null
          : (value) =>
                setState(() => controller.text = value ? widget.label : ''),
    );
  }
}

// ---------------------------------------------------------------------------
// 공지
// ---------------------------------------------------------------------------

class _AiAnnouncementComposerSheet extends StatefulWidget {
  const _AiAnnouncementComposerSheet();

  @override
  State<_AiAnnouncementComposerSheet> createState() =>
      _AiAnnouncementComposerSheetState();
}

class _AiAnnouncementComposerSheetState
    extends State<_AiAnnouncementComposerSheet> {
  final _prompt = TextEditingController();
  final _answers = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;
  AiAnnouncementDraft? _draft;

  @override
  void dispose() {
    _prompt.dispose();
    for (final controller in _answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.length < 2 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = await AiComposeService().composeAnnouncement(prompt: prompt);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _busy = false;
        for (final question in draft.questions) {
          _answers.putIfAbsent(question.field, TextEditingController.new);
        }
      });
    } on AiComposeException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  AiAnnouncementDraft _applyAnswers(AiAnnouncementDraft draft) {
    String answer(String field) => _answers[field]?.text.trim() ?? '';
    return AiAnnouncementDraft(
      summary: draft.summary,
      title: answer('title').isEmpty ? draft.title : answer('title'),
      body: answer('body').isEmpty ? draft.body : answer('body'),
      pinned: draft.pinned,
      pollQuestion: draft.pollQuestion,
      pollOptions: draft.pollOptions,
      questions: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: EncbaColors.snuBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI로 공지 채우기',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '대충 편하게 말씀해주세요~',
              style: TextStyle(
                color: EncbaColors.muted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            _AiPromptField(
              controller: _prompt,
              hintText: '이번 주 훈련 장소가 신체육관으로 바뀌었다고 알려주세요',
              enabled: !_busy,
            ),
            if (_error case final String message) _AiErrorText(message: message),
            if (_busy) ...[
              const SizedBox(height: 14),
              const _AiProgressBar(label: 'AI가 공지를 쓰고 있습니다'),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(
                _busy
                    ? '쓰는 중…'
                    : draft == null
                    ? '공지 초안 만들기'
                    : '다시 쓰기',
              ),
            ),
            if (draft != null) ...[
              const SizedBox(height: 18),
              if (draft.questions.isNotEmpty) ...[
                _AiQuestionsCard(
                  questions: draft.questions,
                  controllers: _answers,
                  optionsFor: (_) => null,
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.title.isEmpty ? '(제목 없음)' : draft.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        draft.body.isEmpty ? '(내용 없음)' : draft.body,
                        style: const TextStyle(height: 1.6),
                      ),
                      if (draft.pollOptions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          draft.pollQuestion.isEmpty
                              ? '투표 항목'
                              : '투표 · ${draft.pollQuestion}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          draft.pollOptions.join(' · '),
                          style: const TextStyle(
                            color: EncbaColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context, _applyAnswers(draft)),
                child: const Text('이 내용으로 채우기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// AI가 답을 만드는 동안 보여 주는 진행 막대.
///
/// 서버가 진행률을 알려 주지 않으므로(한 번 부르고 한 번 받는다) 실제
/// 백분율은 알 수 없다. 그래서 지금까지 걸린 시간을 [expected]에 견줘
/// 추정치를 그린다. 끝나갈수록 천천히 올라가고 95%에서 멈춰, 다 되기 전에
/// 100%가 떠서 "다 됐는데 왜 안 넘어가지" 하는 오해를 만들지 않는다.
class _AiProgressBar extends StatefulWidget {
  const _AiProgressBar({required this.label});

  final String label;

  /// 보통 이 정도 걸린다고 보는 시간. 학기 전체를 펼치는 요청이 가장
  /// 오래 걸려서 그쪽에 맞춰 잡았다.
  static const expected = Duration(seconds: 18);

  @override
  State<_AiProgressBar> createState() => _AiProgressBarState();
}

class _AiProgressBarState extends State<_AiProgressBar> {
  final _stopwatch = Stopwatch()..start();
  Timer? _ticker;
  double _progress = 0;

  static const _ceiling = .95;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final elapsed = _stopwatch.elapsedMilliseconds;
      final expected = _AiProgressBar.expected.inMilliseconds;
      // 1 - e^(-t/T): 처음엔 빠르게, 뒤로 갈수록 느리게 찬다.
      final eased = 1 - math.exp(-elapsed / expected);
      setState(() => _progress = (eased * _ceiling).clamp(0.0, _ceiling));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: EncbaColors.navy,
              ),
            ),
          ),
          Text(
            '${(_progress * 100).round()}%',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: EncbaColors.snuBlue,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: _progress,
          minHeight: 8,
          color: EncbaColors.snuBlue,
          backgroundColor: EncbaColors.line,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        _stopwatch.elapsed.inSeconds < 20
            ? '요청을 읽고 있습니다…'
            : '거의 다 됐습니다. 조금만 기다려 주세요…',
        style: const TextStyle(color: EncbaColors.muted, fontSize: 11),
      ),
    ],
  );
}
