import 'dart:convert';

import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/core/widgets/wheel_picker_field.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// 학번 피커의 선택지. 오래된 부원도 편집할 수 있어야 하므로 00~99 전체를 다룬다
/// (가입 화면의 00~25 범위와 달리, 여기서는 최근 가입자로 좁힐 이유가 없다).
final List<String> _editStudentYearOptions = List.generate(
  100,
  (i) => (99 - i).toString().padLeft(2, '0'),
);

/// 가입년도 피커의 선택지. 동아리 창립 연도(1977)부터 올해까지 전부 다룬다.
final List<String> _editJoinedYearOptions = List.generate(
  DateTime.now().year - 1977 + 1,
  (i) => (DateTime.now().year - i).toString(),
);

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _jerseyNumber;
  late String _position;
  late String _studentYearPick;
  late String _joinedYearPick;
  String? _photoBase64;
  bool _photoChanged = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user!;
    _name = TextEditingController(text: user.name);
    final rawStudentYear = user.studentId.replaceAll('학번', '').trim();
    _studentYearPick = _editStudentYearOptions.contains(rawStudentYear)
        ? rawStudentYear
        : _editStudentYearOptions.first;
    final rawJoinedYear = '${user.joinedYear ?? DateTime.now().year}';
    _joinedYearPick = _editJoinedYearOptions.contains(rawJoinedYear)
        ? rawJoinedYear
        : _editJoinedYearOptions.first;
    _phone = TextEditingController(text: user.phone);
    _jerseyNumber = TextEditingController(text: '${user.jerseyNumber}');
    _position = user.position;
    _photoBase64 = user.photoBase64;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _jerseyNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('내 정보 수정')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Center(
              child: InkWell(
                onTap: _pickPhoto,
                borderRadius: BorderRadius.circular(54),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: EncbaColors.highlight,
                      backgroundImage: _photoBase64 == null
                          ? null
                          : MemoryImage(base64Decode(_photoBase64!)),
                      child: _photoBase64 == null
                          ? Text(
                              _name.text.isEmpty ? 'E' : _name.text[0],
                              style: const TextStyle(
                                fontSize: 32,
                                color: EncbaColors.deepBlue,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          color: EncbaColors.snuBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: EncbaColors.highlight,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white,
                    backgroundImage: _photoBase64 == null
                        ? null
                        : MemoryImage(base64Decode(_photoBase64!)),
                    child: _photoBase64 == null
                        ? Text(_name.text.isEmpty ? 'E' : _name.text[0])
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name.text,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('$_position · #${_jerseyNumber.text}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: '실명',
                helperText: '다른 부원에게도 이 이름으로 표시됩니다.',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: WheelPickerField(
                    label: '학번',
                    value: _studentYearPick,
                    options: _editStudentYearOptions,
                    onChanged: (value) =>
                        setState(() => _studentYearPick = value),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: WheelPickerField(
                    label: '엔크바 가입 년도',
                    value: _joinedYearPick,
                    options: _editJoinedYearOptions,
                    onChanged: (value) =>
                        setState(() => _joinedYearPick = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: '전화번호 *'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _position,
              decoration: const InputDecoration(labelText: '포지션'),
              items: const ['미정', 'PG', 'SG', 'SF', 'PF', 'C']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _position = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _jerseyNumber,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '등번호 *'),
              validator: (value) =>
                  int.tryParse(value ?? '') == null ? '숫자를 입력하세요.' : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: auth.isBusy ? null : _save,
              child: Text(auth.isBusy ? '저장 중…' : '내 정보 저장'),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '필수 항목입니다.' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authControllerProvider).user!;
    final saved = await ref
        .read(authControllerProvider.notifier)
        .updateProfile(
          user.copyWith(
            displayName: user.name,
            studentId: '$_studentYearPick학번',
            joinedYear: int.parse(_joinedYearPick),
            phone: _phone.text.trim(),
            position: _position,
            jerseyNumber: int.parse(_jerseyNumber.text),
            photoBase64: _photoBase64,
            clearPhoto: !_photoChanged,
          ),
        );
    if (mounted && saved) Navigator.pop(context);
  }

  Future<void> _pickPhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 72,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photoBase64 = base64Encode(bytes);
      _photoChanged = true;
    });
  }
}
