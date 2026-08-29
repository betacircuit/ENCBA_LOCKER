import 'package:encba_locker/core/widgets/wheel_picker_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final thisYear = DateTime.now().year;

  test('학번 목록의 맨 위는 올해 학번이다', () {
    // 2026년이면 26학번이 첫 줄이어야 한다. 예전에는 25까지만 적어 둬서
    // 해가 바뀌면 새 학번을 아예 고를 수 없었다.
    final expected = (thisYear % 100).toString().padLeft(2, '0');

    expect(studentYearPickerOptions.first, expected);
  });

  test('가입년도 목록의 맨 위는 올해다', () {
    expect(joinedYearPickerOptions.first, thisYear.toString());
  });

  test('학번은 최근 연도부터 거슬러 내려간다', () {
    final options = studentYearPickerOptions;

    expect(options, hasLength(26));
    expect(
      options[1],
      ((thisYear - 1) % 100).toString().padLeft(2, '0'),
    );
    // 두 자리로 맞춰야 정렬과 표시가 흐트러지지 않는다.
    expect(options.every((value) => value.length == 2), isTrue);
    expect(options.toSet(), hasLength(options.length));
  });

  test('가입년도는 창립 연도보다 앞서지 않는다', () {
    for (final year in joinedYearPickerOptions) {
      expect(int.parse(year), greaterThanOrEqualTo(encbaFoundedYear));
      expect(int.parse(year), lessThanOrEqualTo(thisYear));
    }
  });
}
