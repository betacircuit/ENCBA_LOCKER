part of '../locker_shell.dart';

/// [member]가 null이면 구글 로그인 대조용 가입 명단에 아직 없는 사람을
/// 새로 등록하는 화면이 된다.
Future<void> _showMemberEditor(
  BuildContext context,
  WidgetRef ref,
  MemberProfile? member,
) async {
  final isNew = member == null;
  final base =
      member ??
      const MemberProfile(
        name: '',
        studentId: '',
        generation: 1,
        status: 'YB',
        position: '미정',
        teams: ['ENCBA'],
        note: '',
      );
  final name = TextEditingController(text: base.name);
  final studentYear = TextEditingController(
    text: base.studentId.replaceAll(RegExp(r'[^0-9]'), ''),
  );
  final joinedYear = TextEditingController(
    text: base.joinedYear?.toString() ?? '',
  );
  final phone = TextEditingController(text: base.phone);
  final department = TextEditingController(text: base.department);
  final jersey = TextEditingController(text: base.jerseyNumber.toString());
  final newTitle = TextEditingController();
  var position = base.position;
  var status = base.status;
  var role = base.leadershipRole;
  var isReservationManager = base.isReservationManager;
  var isFreshman = base.isFreshman;
  var isActive = base.isActive;
  var teams = {...base.teams};
  var titles = List<String>.of(base.titles);
  var titleEmoji = defaultMemberTitleEmoji;
  String? validationError;

  // 이모지와 이름을 붙여 한 줄로 저장한다. 이름이 비었거나 이미 있는
  // 직책이면 아무것도 하지 않는다.
  void addTitle() {
    final name = newTitle.text.trim();
    if (name.isEmpty) return;
    final value = '$titleEmoji $name';
    if (titles.any((item) => memberTitleLabel(item) == name)) return;
    titles.add(value);
    newTitle.clear();
    titleEmoji = defaultMemberTitleEmoji;
  }

  final save = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isNew ? '새 멤버 등록' : '멤버 정보 수정',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (isNew) ...[
                  const SizedBox(height: 4),
                  const Text(
                    '구글 로그인 때 대조하는 가입 명단에 실명을 추가합니다. '
                    '이후 본인이 같은 실명으로 학교 Google 계정을 인증하면 가입이 이어집니다.',
                    style: TextStyle(color: EncbaColors.muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '실명'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: studentYear,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '학번'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: joinedYear,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '엔크바 가입 년도',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '전화번호'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: department,
                  decoration: const InputDecoration(labelText: '학과'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: position,
                        decoration: const InputDecoration(labelText: '포지션'),
                        items: const ['PG', 'SG', 'SF', 'PF', 'C', '미정']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => position = value ?? position,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: jersey,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '등번호'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: '직책'),
                  items:
                      const {
                            'member': '부원',
                            'manager': '매니저',
                            'captain': '주장',
                            'admin': '관리자',
                          }.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => role = value ?? role,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '상태'),
                  items:
                      const {
                            'YB': '재학',
                            'OB': 'OB',
                            'MILITARY_LEAVE': '군 휴학',
                            'EXCHANGE_STUDENT': '교환학생',
                            'STUDY_ABROAD': '유학',
                            'GRADUATED': '졸업',
                            'INACTIVE': '비활동',
                          }.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => status = value ?? status,
                ),
                const SizedBox(height: 8),
                const Text('소속'),
                Wrap(
                  spacing: 8,
                  children: ['ENCBA', 'BEN'].map((team) {
                    return FilterChip(
                      label: Text(team),
                      selected: teams.contains(team),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          teams.add(team);
                        } else if (teams.length > 1) {
                          teams.remove(team);
                        }
                      }),
                    );
                  }).toList(),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  title: const Text('계정 활성화'),
                  onChanged: (value) => setState(() => isActive = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: isReservationManager,
                  title: const Text('체육관 예약자'),
                  subtitle: const Text('화요일 09:30 예약 오픈 알림 대상'),
                  onChanged: (value) =>
                      setState(() => isReservationManager = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: isFreshman,
                  title: const Text('신입생'),
                  onChanged: (value) => setState(() => isFreshman = value),
                ),
                const SizedBox(height: 8),
                const Text('직책(표시용, 여러 개 가능)'),
                const SizedBox(height: 6),
                if (titles.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: titles
                        .map(
                          (title) => InputChip(
                            avatar: Text(memberTitleEmoji(title)),
                            label: Text(memberTitleLabel(title)),
                            onDeleted: () =>
                                setState(() => titles.remove(title)),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이모지는 직책 이름 앞에 붙여 저장한다("🎸 밴드부장").
                    // 컬럼을 늘리지 않고도 직책마다 제 얼굴을 가진다.
                    _TitleEmojiButton(
                      emoji: titleEmoji,
                      onChanged: (value) => setState(() => titleEmoji = value),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: newTitle,
                        decoration: const InputDecoration(
                          labelText: '직책 추가',
                          hintText: '예: 벤 감독',
                        ),
                        onSubmitted: (_) => setState(addTitle),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '추가',
                      onPressed: () => setState(addTitle),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final joined = int.tryParse(joinedYear.text.trim());
                    final number = int.tryParse(jersey.text.trim());
                    if (name.text.trim().isEmpty ||
                        (joined != null && (joined < 1977 || joined > 2100)) ||
                        number == null ||
                        number < 0 ||
                        number > 99) {
                      setState(
                        () => validationError =
                            '이름과 등번호를 확인해 주세요. 가입 연도는 비어 있어도 됩니다.',
                      );
                      return;
                    }
                    Navigator.pop(sheetContext, true);
                  },
                  child: Text(isNew ? '멤버 등록' : '변경 사항 저장'),
                ),
                if (validationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (save == true) {
    final updated = base.copyWith(
      name: name.text.trim(),
      studentId: '${studentYear.text.trim()}학번',
      joinedYear: int.tryParse(joinedYear.text.trim()),
      phone: phone.text.trim(),
      position: position,
      jerseyNumber: int.parse(jersey.text.trim()),
      status: status,
      teams: teams.toList()..sort(),
      leadershipRole: role,
      isActive: isActive,
      isReservationManager: isReservationManager,
      department: department.text.trim(),
      isFreshman: isFreshman,
      titles: titles,
    );
    final notifier = ref.read(lockerControllerProvider.notifier);
    final failure = isNew
        ? await notifier.addMember(updated)
        : await notifier.updateMember(updated);
    if (context.mounted && failure != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isNew ? '멤버를 등록하지 못했습니다' : '멤버 정보를 저장하지 못했습니다'),
          content: Text(failure),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }
  name.dispose();
  studentYear.dispose();
  joinedYear.dispose();
  phone.dispose();
  department.dispose();
  newTitle.dispose();
  jersey.dispose();
}


/// 직책 앞에 붙일 이모지를 고르는 작은 버튼. 목록에 없는 이모지는 직접
/// 붙여 넣을 수 있어 아이폰·갤럭시 키보드에서 고른 것도 그대로 쓴다.
class _TitleEmojiButton extends StatelessWidget {
  const _TitleEmojiButton({required this.emoji, required this.onChanged});

  final String emoji;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _pick(context),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: 54,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EncbaColors.line),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 22)),
    ),
  );

  Future<void> _pick(BuildContext context) async {
    final controller = TextEditingController(text: emoji);
    final picked = await showModalBottomSheet<String>(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('직책 이모지', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                '목록에서 고르거나, 키보드에서 고른 이모지를 아래에 붙여 넣으세요.',
                style: TextStyle(color: EncbaColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in memberTitleEmojiChoices)
                    InkWell(
                      onTap: () => Navigator.pop(sheetContext, choice),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: choice == emoji
                              ? EncbaColors.highlight
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: choice == emoji
                                ? EncbaColors.snuBlue
                                : EncbaColors.line,
                          ),
                        ),
                        child: Text(
                          choice,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLength: 8,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22),
                decoration: const InputDecoration(
                  labelText: '직접 입력',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  final typed = controller.text.trim();
                  Navigator.pop(
                    sheetContext,
                    typed.isEmpty ? defaultMemberTitleEmoji : typed,
                  );
                },
                child: const Text('이 이모지 쓰기'),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (picked != null && picked.isNotEmpty) onChanged(picked);
  }
}
