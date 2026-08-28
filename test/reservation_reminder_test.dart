import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 2026년 8월 29일은 토요일이다. 다음 화요일은 9월 1일.
  final saturday = DateTime(2026, 8, 29, 14);

  test('예약은 다음 화요일 09:30에 열린다', () {
    expect(
      nextCourtReservationOpening(saturday),
      DateTime(2026, 9, 1, 9, 30),
    );
  });

  test('화요일 09:30 정각 전에는 그날이, 지난 뒤에는 다음 주가 목표다', () {
    expect(
      nextCourtReservationOpening(DateTime(2026, 9, 1, 9, 29)),
      DateTime(2026, 9, 1, 9, 30),
    );
    expect(
      nextCourtReservationOpening(DateTime(2026, 9, 1, 9, 30)),
      DateTime(2026, 9, 8, 9, 30),
    );
  });

  test('알림은 전날 22시와 당일 09시에 울린다', () {
    final times = courtReservationReminderTimes(DateTime(2026, 9, 1, 9, 30));

    // 오픈 전날(월요일) 밤 10시.
    expect(times.eve, DateTime(2026, 8, 31, 22));
    expect(times.eve.weekday, DateTime.monday);
    // 오픈 당일(화요일) 오전 9시 = 오픈 30분 전.
    expect(times.morning, DateTime(2026, 9, 1, 9));
    expect(times.morning.weekday, DateTime.tuesday);
    expect(
      DateTime(2026, 9, 1, 9, 30).difference(times.morning),
      const Duration(minutes: 30),
    );
  });

  test('예약 창이 열려 있는 동안에는 다음 오픈이 3일 뒤다', () {
    // 화면에서 본 상황: 8/29(토) 07:37에 카운트다운이 1일 16시간이었다.
    // 그건 다음 오픈까지가 아니라 이번 예약 창이 닫힐 때까지였다.
    // 다음 오픈은 9/1(화) 09:30이라 사흘이 넘는다.
    final now = DateTime(2026, 8, 29, 7, 37, 41);
    final opening = nextCourtReservationOpening(now);

    expect(opening, DateTime(2026, 9, 1, 9, 30));
    expect(opening.difference(now).inDays, 3);
  });

  test('달이 바뀌는 경계에서도 전날 22시를 제대로 잡는다', () {
    // 2026년 9월 1일이 화요일이므로 전날은 8월 31일이다.
    final times = courtReservationReminderTimes(DateTime(2026, 9, 1, 9, 30));
    expect(times.eve.month, 8);
    expect(times.eve.day, 31);
  });
}
