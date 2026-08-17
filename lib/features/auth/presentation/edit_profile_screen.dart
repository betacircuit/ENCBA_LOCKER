import 'dart:convert';

import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _displayName;
  late final TextEditingController _studentId;
  late final TextEditingController _joinedYear;
  late final TextEditingController _phone;
  late final TextEditingController _jerseyNumber;
  late String _position;
  String? _photoBase64;
  bool _photoChanged = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user!;
    _name = TextEditingController(text: user.name);
    _displayName = TextEditingController(text: user.visibleName);
    _studentId = TextEditingController(
      text: user.studentId.replaceAll('학번', ''),
    );
    _joinedYear = TextEditingController(
      text: '${user.joinedYear ?? DateTime.now().year}',
    );
    _phone = TextEditingController(text: user.phone);
    _jerseyNumber = TextEditingController(text: '${user.jerseyNumber}');
    _position = user.position;
    _photoBase64 = user.photoBase64;
  }

  @override
  void dispose() {
    _name.dispose();
    _displayName.dispose();
    _studentId.dispose();
    _joinedYear.dispose();
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
                        ? Text(
                            _displayName.text.isEmpty
                                ? 'E'
                                : _displayName.text[0],
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName.text.trim().isEmpty
                              ? _name.text
                              : _displayName.text.trim(),
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
              decoration: const InputDecoration(labelText: '가입 실명'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _displayName,
              decoration: const InputDecoration(labelText: '다른 부원에게 보이는 이름 *'),
              onChanged: (_) => setState(() {}),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _studentId,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '학번 *'),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      return parsed == null || parsed < 0 || parsed > 99
                          ? '00–99로 입력하세요.'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _joinedYear,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '엔크바 가입 년도 *'),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      return parsed == null || parsed < 1977 || parsed > 2100
                          ? '연도를 확인하세요.'
                          : null;
                    },
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
            displayName: _displayName.text.trim(),
            studentId:
                '${int.parse(_studentId.text.trim()).toString().padLeft(2, '0')}학번',
            joinedYear: int.parse(_joinedYear.text.trim()),
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
