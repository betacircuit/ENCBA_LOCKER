import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _name = TextEditingController();
  final _studentId = TextEditingController();
  final _generation = TextEditingController();
  final _phone = TextEditingController();
  final _jerseyNumber = TextEditingController();
  bool _signUp = false;
  bool _obscure = true;
  String _position = 'PG';

  @override
  void dispose() {
    for (final controller in [
      _password,
      _passwordConfirm,
      _name,
      _studentId,
      _generation,
      _phone,
      _jerseyNumber,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ClubMark(),
                  const SizedBox(height: 28),
                  Text(
                    _signUp ? '라커에 자리 만들기' : 'Welcome to ENCBA',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 28),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: Column(
                      children: [
                        if (_signUp) ...[
                          _Field(
                            controller: _studentId,
                            label: '학번',
                            hint: '22',
                            keyboardType: TextInputType.number,
                            validator: _required,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _Field(
                                  controller: _generation,
                                  label: '기수',
                                  hint: '41',
                                  keyboardType: TextInputType.number,
                                  validator: (value) =>
                                      int.tryParse(value ?? '') == null
                                      ? '숫자로 입력해 주세요.'
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _position,
                                  decoration: const InputDecoration(
                                    labelText: '포지션',
                                  ),
                                  items: const ['PG', 'SG', 'SF', 'PF', 'C']
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(value),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) => _position = value!,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _Field(
                                  controller: _jerseyNumber,
                                  label: '등번호',
                                  hint: '23',
                                  keyboardType: TextInputType.number,
                                  validator: (value) =>
                                      int.tryParse(value ?? '') == null
                                      ? '숫자를 입력해 주세요.'
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _Field(
                            controller: _phone,
                            label: '전화번호',
                            hint: '010-1234-5678',
                            keyboardType: TextInputType.phone,
                            validator: _required,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _Field(
                          controller: _name,
                          label: '실명',
                          hint: '가입 명단과 동일하게 입력',
                          autofillHints: const [AutofillHints.name],
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: _password,
                          label: '비밀번호',
                          obscureText: _obscure,
                          autofillHints: _signUp
                              ? const [AutofillHints.newPassword]
                              : const [AutofillHints.password],
                          suffix: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          validator: (value) => (value?.length ?? 0) < 8
                              ? '8자 이상 입력해 주세요.'
                              : null,
                        ),
                        if (_signUp) ...[
                          const SizedBox(height: 12),
                          _Field(
                            controller: _passwordConfirm,
                            label: '비밀번호 확인',
                            obscureText: _obscure,
                            validator: (value) => value != _password.text
                                ? '비밀번호가 일치하지 않습니다.'
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      auth.error!,
                      style: const TextStyle(
                        color: EncbaColors.absent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: auth.isBusy ? null : _submit,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: auth.isBusy
                          ? const SizedBox(
                              key: ValueKey('busy'),
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _signUp ? '가입하고 시작' : '로그인',
                              key: const ValueKey('label'),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: auth.isBusy
                        ? null
                        : () => setState(() {
                            _signUp = !_signUp;
                            _formKey.currentState?.reset();
                          }),
                    child: Text(_signUp ? '이미 계정이 있어요' : '처음이라면 회원가입'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '입력해 주세요.' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final controller = ref.read(authControllerProvider.notifier);
    if (_signUp) {
      await controller.signUp(
        UserProfile(
          email: '',
          name: _name.text.trim(),
          studentId: '${_studentId.text.trim()}학번',
          generation: int.parse(_generation.text.trim()),
          phone: _phone.text.trim(),
          position: _position,
          jerseyNumber: int.parse(_jerseyNumber.text),
          status: 'YB',
          teams: const ['ENCBA'],
        ),
        _password.text,
      );
    } else {
      await controller.signIn(_name.text.trim(), _password.text);
    }
  }
}

class _ClubMark extends StatelessWidget {
  const _ClubMark();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Image.asset(
        'assets/images/encba_logo.png',
        width: 64,
        height: 64,
        fit: BoxFit.contain,
      ),
      const SizedBox(width: 10),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ENCBA',
            style: TextStyle(
              fontFamily: 'BlackHanSans',
              fontSize: 28,
              height: 1,
              color: EncbaColors.navy,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'ENGINEERING BASKETBALL · SINCE 1977',
            style: TextStyle(
              fontFamily: 'Arial',
              fontSize: 8.5,
              letterSpacing: .8,
              color: EncbaColors.muted,
            ),
          ),
        ],
      ),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.suffix,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    obscureText: obscureText,
    validator: validator,
    autofillHints: autofillHints,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
    ),
  );
}
