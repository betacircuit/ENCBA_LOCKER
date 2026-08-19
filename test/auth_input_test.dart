import 'package:encba_locker/features/auth/data/supabase_auth_repository.dart';
import 'package:encba_locker/features/auth/presentation/auth_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  const formatter = KoreanMobilePhoneFormatter();

  TextEditingValue value(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  test('전화번호는 010으로 시작하고 네 자리 뒤에 하이픈을 붙인다', () {
    expect(formatter.formatEditUpdate(value(''), value('')).text, '010-');
    expect(
      formatter.formatEditUpdate(value('010-123'), value('010-1234')).text,
      '010-1234',
    );
    expect(
      formatter.formatEditUpdate(value('010-1234'), value('010-12345')).text,
      '010-1234-5',
    );
    expect(
      formatter
          .formatEditUpdate(value('010-1234-567'), value('010-1234-5678'))
          .text,
      '010-1234-5678',
    );
  });

  test('자동 하이픈에서 백스페이스를 누르면 앞 숫자가 자연스럽게 지워진다', () {
    final result = formatter.formatEditUpdate(
      value('010-1234-'),
      value('010-1234'),
    );

    expect(result.text, '010-123');
    expect(result.selection.baseOffset, result.text.length);
  });

  test('Supabase same_password 오류는 Google 가입 재시도로 처리한다', () {
    const error = supabase.AuthApiException(
      'New password should be different from the old password.',
      statusCode: '422',
      code: 'same_password',
    );

    expect(isReusableGoogleRegistrationPasswordError(error), isTrue);
  });
}
