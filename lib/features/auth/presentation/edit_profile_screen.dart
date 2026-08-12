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
  late final TextEditingController _studentId;
  late final TextEditingController _generation;
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
    _studentId = TextEditingController(
      text: user.studentId.replaceAll('학번', ''),
    );
    _generation = TextEditingController(text: '${user.generation}');
    _phone = TextEditingController(text: user.phone);
    _jerseyNumber = TextEditingController(text: '${user.jerseyNumber}');
    _position = user.position;
    _photoBase64 = user.photoBase64;
  }

  @override
  void dispose() {
    _name.dispose();
    _studentId.dispose();
    _generation.dispose();
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
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '이름 *'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _studentId,
                    keyboardType: TextInputType.number,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: '학번 *'),
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _generation,
                    keyboardType: TextInputType.number,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: '기수 *'),
                    validator: (value) =>
                        int.tryParse(value ?? '') == null ? '숫자를 입력하세요.' : null,
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
              onChanged: (value) => _position = value!,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _jerseyNumber,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '등번호 *'),
              validator: (value) =>
                  int.tryParse(value ?? '') == null ? '숫자를 입력하세요.' : null,
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
            name: _name.text.trim(),
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
