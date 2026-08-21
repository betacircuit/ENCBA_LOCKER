import 'package:encba_locker/features/auth/data/supabase_auth_repository.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:encba_locker/features/auth/presentation/auth_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      '010-1234-',
    );
    expect(
      formatter.formatEditUpdate(value('010-1234-'), value('010-1234-5')).text,
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

  test('전체 삭제·다시 입력·붙여넣기에도 010 접두사와 하이픈을 복원한다', () {
    final cleared = formatter.formatEditUpdate(
      value('010-1234-5678'),
      value(''),
    );
    expect(cleared.text, '010-');

    final retyped = formatter.formatEditUpdate(cleared, value('010-9876'));
    expect(retyped.text, '010-9876-');

    final pasted = formatter.formatEditUpdate(value('010-'), value('40953346'));
    expect(pasted.text, '010-4095-3346');
  });

  test('서울대 Google 표시명에서 가입 명단용 실명만 추출한다', () {
    expect(
      googleRealNameFromMetadata(const {
        'full_name': '\u00ad최재원 / 학생 / 전기·정보공학부',
      }),
      '최재원',
    );
  });

  test('실명 로그인 주소는 이메일 대소문자 정규화에도 충돌하지 않는다', () {
    final first = internalLoginEmailForName('가');
    final second = internalLoginEmailForName('갚');

    expect(first, isNot(equals(second)));
    expect(first, first.toLowerCase());
    expect(second, second.toLowerCase());
    expect(first.split('@').first.length, lessThanOrEqualTo(64));
    expect(
      internalLoginEmailForName('가나다라마바사아자차카타파하').split('@').first.length,
      lessThanOrEqualTo(64),
    );
  });

  test('다른 부원에게 보이는 이름은 별칭이 있어도 실명이다', () {
    const profile = UserProfile(
      email: 'member@snu.ac.kr',
      name: '김실명',
      displayName: '별명',
      studentId: '24학번',
      generation: 43,
      phone: '010-0000-0000',
      position: 'PG',
      jerseyNumber: 1,
      status: 'YB',
      teams: ['ENCBA'],
    );

    expect(profile.visibleName, '김실명');
  });
}
