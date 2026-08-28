part of '../locker_shell.dart';

/// AI 채우기 시트. 프롬프트 한 줄을 받아 초안을 만들고, AI가 정하지 못한
/// 항목만 골라 되물은 뒤 결과를 돌려준다. 되묻는 항목은 비워 둔 채
/// 넘어갈 수 있다 - 그때는 기존 기본값이 그대로 쓰인다.
///
/// Anthropic API 키는 `ai-compose` 엣지 함수의 환경변수에만 있고 앱에는
/// 내려오지 않는다.

const _aiEventPromptExamples = [
  '이번 학기 동안 매주 화요일 20시부터 22시까지 71동 종합체육관에서 정기훈련',
  '다음 달 첫째 주 토요일 오전 8시 아침 농구',
  '11월 15일 스티즈와 연습경기, 종합체육관 13시',
];

const _aiAnnouncementPromptExamples = [
  '이번 주 정기훈련 장소가 신체육관으로 바뀐다는 공지',
  '엠티 참석 여부를 투표로 받는 공지',
  '기말고사 기간 훈련 휴식 안내',
];

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

/// 프롬프트 입력 칸과 예시. 두 시트가 같은 모양을 쓴다.
class _AiPromptField extends StatelessWidget {
  const _AiPromptField({
    required this.controller,
    required this.examples,
    required this.hintText,
    required this.enabled,
  });

  final TextEditingController controller;
  final List<String> examples;
  final String hintText;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
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
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final example in examples)
            ActionChip(
              label: Text(
                example.length > 22 ? '${example.substring(0, 22)}…' : example,
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: enabled ? () => controller.text = example : null,
            ),
        ],
      ),
    ],
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
                const Icon(Icons.auto_awesome_rounded, color: EncbaColors.snuBlue),
                const SizedBox(width: 8),
                Text('AI로 일정 채우기', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '"이번 학기 동안 매주 …"처럼 적으면 기간 전체를 펼쳐서 만들어 줍니다. '
              '만든 뒤에도 하나씩 확인하고 지울 수 있습니다.',
              style: TextStyle(
                color: EncbaColors.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            _AiPromptField(
              controller: _prompt,
              examples: _aiEventPromptExamples,
              hintText: '예: 이번 학기 동안 매주 화요일 20–22시 종합체육관 정기훈련',
              enabled: !_busy,
            ),
            if (_error case final String message) _AiErrorText(message: message),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
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
              '무엇을 알리고 싶은지만 적으면 제목·내용·투표까지 채워 줍니다. '
              '채운 뒤에도 그대로 고칠 수 있습니다.',
              style: TextStyle(
                color: EncbaColors.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            _AiPromptField(
              controller: _prompt,
              examples: _aiAnnouncementPromptExamples,
              hintText: '예: 이번 주 정기훈련 장소가 신체육관으로 바뀐다는 공지',
              enabled: !_busy,
            ),
            if (_error case final String message) _AiErrorText(message: message),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
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
