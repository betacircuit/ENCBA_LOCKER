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
  final _joinedYear = TextEditingController();
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
      _joinedYear,
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
    final pendingRegistration = auth.pendingRegistration;
    final isRegistration = _signUp || pendingRegistration != null;
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
                    pendingRegistration != null
                        ? '회원 정보 입력'
                        : _signUp
                        ? 'Google로 가입하기'
                        : 'Welcome to ENCBA',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontFamily: encbaFontFor(
                        pendingRegistration != null
                            ? '회원 정보 입력'
                            : _signUp
                            ? 'Google로 가입하기'
                            : 'Welcome to ENCBA',
                        display: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: Column(
                      children: [
                        if (pendingRegistration != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: EncbaColors.highlight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '학교 계정 확인 완료',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  pendingRegistration.email,
                                  style: const TextStyle(
                                    color: EncbaColors.muted,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '이 주소가 로그인 아이디가 됩니다. 아래에서 비밀번호를 정하면 '
                                  'Google 없이도 로그인할 수 있습니다.',
                                  style: TextStyle(
                                    color: EncbaColors.muted,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _Field(
                            controller: _name,
                            label: '실명',
                            hint: pendingRegistration.suggestedName.isEmpty
                                ? '가입 명단과 동일하게 입력'
                                : '${pendingRegistration.suggestedName} · 가입 명단과 동일하게',
                            autofillHints: const [AutofillHints.name],
                            validator: _required,
                          ),
                          const SizedBox(height: 12),
                          _Field(
                            controller: _studentId,
                            label: '학번',
                            hint: '22',
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              final year = int.tryParse(value ?? '');
                              return year == null || year < 0 || year > 99
                                  ? '00–99로 입력해 주세요.'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _Field(
                                  controller: _joinedYear,
                                  label: '엔크바 가입 년도',
                                  hint: '${DateTime.now().year}',
                                  keyboardType: TextInputType.number,
                                  validator: (value) {
                                    final year = int.tryParse(value ?? '');
                                    if (year == null ||
                                        year < 1977 ||
                                        year > DateTime.now().year) {
                                      return '올바른 가입 년도를 입력해 주세요.';
                                    }
                                    return null;
                                  },
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
                                  validator: (value) {
                                    final number = int.tryParse(value ?? '');
                                    return number == null ||
                                            number < 0 ||
                                            number > 99
                                        ? '0–99로 입력해 주세요.'
                                        : null;
                                  },
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
                          _Field(
                            controller: _password,
                            label: '비밀번호',
                            hint: '8자 이상',
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.newPassword],
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
                          const SizedBox(height: 12),
                          _Field(
                            controller: _passwordConfirm,
                            label: '비밀번호 확인',
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.newPassword],
                            validator: (value) => value != _password.text
                                ? '비밀번호가 서로 다릅니다.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ] else if (_signUp) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: EncbaColors.highlight,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Column(
                              children: [
                                Icon(
                                  Icons.school_outlined,
                                  color: EncbaColors.snuBlue,
                                  size: 34,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  '서울대학교 Google 계정으로 인증해 주세요.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'snu.ac.kr 계열 학교 계정과 ENCBA 가입 명단을 모두 확인한 뒤 회원정보를 입력합니다.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: EncbaColors.muted,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          _Field(
                            controller: _name,
                            label: '아이디',
                            hint: '학교 이메일 또는 실명',
                            autofillHints: const [AutofillHints.username],
                            validator: _required,
                          ),
                          const SizedBox(height: 12),
                          _Field(
                            controller: _password,
                            label: '비밀번호',
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
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
                  if (_signUp && pendingRegistration == null)
                    FilledButton.icon(
                      onPressed: auth.isBusy
                          ? null
                          : () => ref
                                .read(authControllerProvider.notifier)
                                .startGoogleSignIn(forSignUp: true),
                      icon: const Icon(Icons.login_rounded),
                      label: Text(
                        auth.isBusy ? 'Google 연결 중…' : 'Google 계정으로 계속',
                      ),
                    )
                  else ...[
                    FilledButton(
                      onPressed: auth.isBusy ? null : _submit,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: auth.isBusy
                            ? const SizedBox(
                                key: ValueKey('busy'),
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                pendingRegistration != null
                                    ? '정보 저장하고 가입 완료'
                                    : '로그인',
                                key: const ValueKey('label'),
                              ),
                      ),
                    ),
                    // 학교 계정을 이미 연결한 부원은 비밀번호 없이 들어온다.
                    // 가입 흐름과 같은 버튼이며, 프로필이 있으면 바로 로그인된다.
                    if (pendingRegistration == null) ...[
                      const SizedBox(height: 14),
                      const _OrDivider(),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: auth.isBusy
                            ? null
                            : () => ref
                                  .read(authControllerProvider.notifier)
                                  .startGoogleSignIn(),
                        icon: const Icon(Icons.school_outlined),
                        label: Text(
                          auth.isBusy ? 'Google 연결 중…' : 'Google 계정으로 로그인',
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: auth.isBusy
                        ? null
                        : () async {
                            if (pendingRegistration != null) {
                              await ref
                                  .read(authControllerProvider.notifier)
                                  .cancelGoogleRegistration();
                              if (mounted) setState(() => _signUp = true);
                              return;
                            }
                            setState(() {
                              _signUp = !_signUp;
                              _formKey.currentState?.reset();
                            });
                          },
                    child: Text(
                      pendingRegistration != null
                          ? '다른 Google 계정 사용'
                          : isRegistration
                          ? '이미 계정이 있어요'
                          : '처음이라면 Google 회원가입',
                    ),
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
    final registration = ref.read(authControllerProvider).pendingRegistration;
    if (registration != null) {
      await controller.completeGoogleRegistration(
        UserProfile(
          email: registration.email,
          name: _name.text.trim(),
          studentId: '${_studentId.text.trim()}학번',
          generation: 1,
          joinedYear: int.parse(_joinedYear.text.trim()),
          phone: _phone.text.trim(),
          position: _position,
          jerseyNumber: int.parse(_jerseyNumber.text),
          status: 'YB',
          teams: const ['ENCBA'],
        ),
        password: _password.text,
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
              fontFamily: 'BlackHanSans',
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

/// 실명 로그인과 학교 계정 로그인을 갈라 주는 구분선.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(child: Divider(color: EncbaColors.line)),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          '또는',
          style: TextStyle(color: EncbaColors.muted, fontSize: 12),
        ),
      ),
      Expanded(child: Divider(color: EncbaColors.line)),
    ],
  );
}
