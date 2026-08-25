import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/presentation/locker_shell.dart';
import 'package:flutter_test/flutter_test.dart';

MemberProfile _member({required String status, bool isActive = true}) =>
    MemberProfile(
      name: '홍길동',
      studentId: '22학번',
      generation: 2022,
      status: status,
      position: 'PG',
      teams: const ['ENCBA'],
      note: '',
      isActive: isActive,
    );

void main() {
  group('멤버 활동 상태 판정', () {
    test('재학·OB는 활동 부원이다', () {
      expect(_member(status: 'YB').isActiveMember, isTrue);
      expect(_member(status: 'OB').isActiveMember, isTrue);
      expect(_member(status: 'YB').isOnLeave, isFalse);
    });

    test('군 휴학·교환학생·유학·비활동은 계정이 살아 있어도 비활성으로 취급한다', () {
      for (final status in [
        'MILITARY_LEAVE',
        'EXCHANGE_STUDENT',
        'STUDY_ABROAD',
        'INACTIVE',
      ]) {
        final member = _member(status: status);
        expect(member.isOnLeave, isTrue, reason: status);
        expect(member.isActiveMember, isFalse, reason: status);
      }
    });

    test('계정이 비활성이면 상태와 무관하게 활동 부원이 아니다', () {
      expect(_member(status: 'YB', isActive: false).isActiveMember, isFalse);
    });
  });

  group('불참 사유 문장 매핑', () {
    test('선택지 라벨과 저장된 문장 모두 원래 카테고리로 되돌아온다', () {
      for (final label in absenceReasonPresets) {
        expect(absenceReasonPresetOf(label), label);
      }
      expect(absenceReasonPresetOf('개인 선약이 있어서 불참합니다.'), '개인 선약');
      expect(absenceReasonPresetOf('부상·건강 문제로 불참합니다.'), '부상·건강');
    });

    test('직접 입력한 사유는 어떤 카테고리로도 분류되지 않는다', () {
      expect(absenceReasonPresetOf('해당 사항 없음'), isNull);
      expect(absenceReasonPresetOf('  '), isNull);
    });
  });

  group('출결 정리 시트 기본 기간', () {
    test('1학기 중에는 지난해 2학기 시작(여름방학 포함)부터가 기본값이다', () {
      expect(previousSemesterStart(DateTime(2026, 4, 15)), DateTime(2025, 9, 1));
      expect(previousSemesterStart(DateTime(2026, 8, 31)), DateTime(2025, 9, 1));
    });

    test('2학기 중에는 같은 해 1학기 시작부터가 기본값이다', () {
      expect(previousSemesterStart(DateTime(2026, 9, 1)), DateTime(2026, 3, 1));
      expect(previousSemesterStart(DateTime(2026, 12, 24)), DateTime(2026, 3, 1));
    });

    test('겨울방학에는 작년 1학기 시작부터가 기본값이다', () {
      expect(previousSemesterStart(DateTime(2026, 1, 10)), DateTime(2025, 3, 1));
      expect(previousSemesterStart(DateTime(2026, 2, 28)), DateTime(2025, 3, 1));
    });
  });
}
