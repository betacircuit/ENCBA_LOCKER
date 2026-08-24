import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/core/widgets/pwa_install_prompt.dart';
import 'package:encba_locker/core/widgets/wheel_picker_field.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _phone = TextEditingController(text: '010-');
  final _jerseyNumber = TextEditingController();
  bool _signUp = false;
  bool _obscure = true;
  String _position = 'PG';
  String _studentYearPick = studentYearPickerOptions.first;
  String _joinedYearPick = joinedYearPickerOptions.first;

  @override
  void dispose() {
    for (final controller in [_password, _passwordConfirm, _phone, _jerseyNumber]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final pendingRegistration = auth.pendingRegistration;
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
                                  'Google 계정은 학교 구성원 확인에만 사용합니다. 로그인 아이디는 '
                                  '아래에 입력한 실명이며, 비밀번호를 정하면 Google 없이도 로그인할 수 있습니다.',
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
                          _VerifiedRealNameField(
                            name: pendingRegistration.suggestedName,
                          ),
                          const SizedBox(height: 12),
                          WheelPickerField(
                            label: '학번',
                            value: _studentYearPick,
                            options: studentYearPickerOptions,
                            onChanged: (value) =>
                                setState(() => _studentYearPick = value),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: WheelPickerField(
                                  label: '엔크바 가입 년도',
                                  value: _joinedYearPick,
                                  options: joinedYearPickerOptions,
                                  onChanged: (value) =>
                                      setState(() => _joinedYearPick = value),
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
                            inputFormatters: const [
                              KoreanMobilePhoneFormatter(),
                            ],
                            validator: (value) =>
                                RegExp(
                                  r'^010-\d{4}-\d{4}$',
                                ).hasMatch(value ?? '')
                                ? null
                                : '010-1234-5678 형식으로 입력해 주세요.',
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
                          // 아이디·비밀번호 로그인은 당분간 비활성화했다.
                          // 실사용은 전부 Google 로그인뿐이라 그 버튼을 이
                          // 자리로 올리고, 아래 빈 자리는 홈 화면 추가
                          // 안내로 채운다. 예전 입력 필드와 비슷한 높이의
                          // 긴 테두리 박스로 두되, 가로도 꽉 채워 늘린다.
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: auth.isBusy
                                  ? null
                                  : () => ref
                                        .read(authControllerProvider.notifier)
                                        .startGoogleSignIn(),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 17),
                                side: const BorderSide(color: EncbaColors.line),
                              ),
                              icon: const Icon(Icons.school_outlined),
                              label: Text(
                                auth.isBusy ? 'Google 연결 중…' : 'Google 계정으로 로그인',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: auth.isBusy
                                  ? null
                                  : () => setState(() {
                                      _signUp = true;
                                      _formKey.currentState?.reset();
                                    }),
                              style: FilledButton.styleFrom(
                                backgroundColor: EncbaColors.snuBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 17),
                              ),
                              icon: const Icon(Icons.school_outlined),
                              label: const Text('처음이라면 Google 회원가입'),
                            ),
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
                  const SizedBox(height: 12),
                  if (_signUp && pendingRegistration == null) ...[
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
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: auth.isBusy
                          ? null
                          : () => setState(() {
                              _signUp = false;
                              _formKey.currentState?.reset();
                            }),
                      child: const Text('이미 계정이 있어요'),
                    ),
                  ] else if (pendingRegistration != null) ...[
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
                            : const Text(
                                '정보 저장하고 가입 완료',
                                key: ValueKey('label'),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: auth.isBusy
                          ? null
                          : () async {
                              await ref
                                  .read(authControllerProvider.notifier)
                                  .cancelGoogleRegistration();
                              if (mounted) setState(() => _signUp = true);
                            },
                      child: const Text('다른 Google 계정 사용'),
                    ),
                  ] else
                    const PwaInstallCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 등록 확정(Google 인증 뒤 회원 정보 입력) 폼 제출. 아이디·비밀번호
  /// 로그인은 비활성화돼 있어 이 버튼은 pendingRegistration이 있을 때만
  /// 노출된다.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final controller = ref.read(authControllerProvider.notifier);
    final registration = ref.read(authControllerProvider).pendingRegistration;
    if (registration == null) return;
    final name = registration.suggestedName.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('학교 계정에서 실명을 확인하지 못했습니다. 관리자에게 문의해 주세요.'),
          ),
        );
      return;
    }
    await controller.completeGoogleRegistration(
      UserProfile(
        email: registration.email,
        name: name,
        studentId: '$_studentYearPick학번',
        generation: 1,
        joinedYear: int.parse(_joinedYearPick),
        phone: _phone.text.trim(),
        position: _position,
        jerseyNumber: int.parse(_jerseyNumber.text),
        status: 'YB',
        teams: const ['ENCBA'],
      ),
      password: _password.text,
    );
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
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    obscureText: obscureText,
    validator: validator,
    autofillHints: autofillHints,
    inputFormatters: inputFormatters,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
    ),
  );
}

/// 국내 휴대전화 번호를 `010-1234-5678` 형태로 유지한다.
///
/// 자동으로 붙은 두 번째 하이픈을 백스페이스로 지우면 하이픈이 즉시 다시
/// 생겨 입력이 막히기 쉽다. 그 경우에는 하이픈 앞 숫자까지 함께 지워서
/// 자연스러운 백스페이스 동작으로 바꾼다.
class KoreanMobilePhoneFormatter extends TextInputFormatter {
  const KoreanMobilePhoneFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldDigits = _digits(oldValue.text);
    var digits = _digits(newValue.text);
    var digitCursor = _digitCountBeforeCursor(newValue);

    if (!digits.startsWith('010')) {
      digits = '010$digits';
      digitCursor += 3;
    }

    final deletedOnlySeparator =
        newValue.text.length < oldValue.text.length &&
        digits == oldDigits &&
        digitCursor > 3;
    if (deletedOnlySeparator) {
      final removeAt = digitCursor - 1;
      digits = digits.substring(0, removeAt) + digits.substring(removeAt + 1);
      digitCursor--;
      final formatted = _format(digits);
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(
          offset: _cursorAfterDigits(formatted, digitCursor),
        ),
      );
    }

    if (digits.length > 11) digits = digits.substring(0, 11);
    if (digitCursor > digits.length) digitCursor = digits.length;

    final formatted = _format(digits);
    final cursor = _cursorAfterDigits(formatted, digitCursor);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  static int _digitCountBeforeCursor(TextEditingValue value) {
    final offset = value.selection.baseOffset.clamp(0, value.text.length);
    return _digits(value.text.substring(0, offset)).length;
  }

  static String _format(String digits) {
    final subscriber = digits.length <= 3 ? '' : digits.substring(3);
    if (subscriber.length < 4) return '010-$subscriber';
    if (subscriber.length == 4) return '010-$subscriber-';
    return '010-${subscriber.substring(0, 4)}-${subscriber.substring(4)}';
  }

  static int _cursorAfterDigits(String value, int digitCount) {
    var seen = 0;
    for (var index = 0; index < value.length; index++) {
      if (RegExp(r'[0-9]').hasMatch(value[index])) seen++;
      if (seen == digitCount) {
        var offset = index + 1;
        if (offset < value.length && value[offset] == '-') offset++;
        return offset;
      }
    }
    return value.length;
  }
}

/// 학교 Google 디렉터리에서 확인한 실명이다. 이메일 대신 이 값이 로그인
/// 아이디가 되며, 가입 명단 선점을 막기 위해 사용자가 임의로 바꿀 수 없다.
class _VerifiedRealNameField extends StatelessWidget {
  const _VerifiedRealNameField({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      border: Border.all(color: EncbaColors.line),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.badge_outlined, color: EncbaColors.snuBlue, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '로그인 아이디 (실명)',
                style: TextStyle(color: EncbaColors.muted, fontSize: 11.5),
              ),
              const SizedBox(height: 2),
              Text(
                name.isEmpty ? '실명을 확인하지 못했습니다' : name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '학교 Google 계정에서 확인된 실명이며, 이 이름으로 로그인합니다.',
                style: TextStyle(color: EncbaColors.muted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
