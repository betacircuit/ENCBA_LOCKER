import 'package:encba_locker/features/locker/presentation/locker_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('네 학기의 시작일을 모두 알려 준다', () {
    final starts = academicTermStarts(2026);

    expect(starts.map((item) => item.term), AcademicTerm.values);
    expect(starts.map((item) => '${item.start.month}.${item.start.day}'), [
      '3.1',
      '6.16',
      '9.1',
      '12.15',
    ]);
  });

  test('날짜가 속한 학기를 짚어 준다', () {
    expect(academicTermOf(DateTime(2026, 4, 10)).term, AcademicTerm.spring);
    expect(academicTermOf(DateTime(2026, 7, 20)).term, AcademicTerm.summer);
    expect(academicTermOf(DateTime(2026, 10, 2)).term, AcademicTerm.fall);
    expect(academicTermOf(DateTime(2026, 12, 20)).term, AcademicTerm.winter);
  });

  test('1~2월은 지난해 겨울학기의 연장이다', () {
    final term = academicTermOf(DateTime(2026, 1, 15));

    expect(term.term, AcademicTerm.winter);
    expect(term.start, DateTime(2025, 12, 15));
  });

  test('출결 시트가 강조하는 날은 직전 정규학기 시작일이다', () {
    // 5월(1학기)에 보면 직전 학기는 지난해 2학기다.
    expect(attendanceRangeAnchor(DateTime(2026, 5, 3)), DateTime(2025, 9, 1));
    // 10월(2학기)에 보면 직전 학기는 올해 1학기다.
    expect(attendanceRangeAnchor(DateTime(2026, 10, 3)), DateTime(2026, 3, 1));
    // 1월(겨울방학)에 보면 직전 학기는 지난해 1학기다.
    expect(attendanceRangeAnchor(DateTime(2026, 1, 20)), DateTime(2025, 3, 1));
  });
}
