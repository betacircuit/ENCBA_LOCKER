import 'package:encba_locker/core/widgets/gentle_scroll_behavior.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('홈커밍 캠페인은 붉은 홈커밍 일정으로 변환된다', () {
    final campaign = HomecomingCampaign(
      id: 'campaign-2026',
      title: '2026 홈커밍',
      academicYear: 2026,
      term: 2,
      eventDate: DateTime(2026, 11, 7),
      startsAt: '14:30:00',
      endsAt: '18:00:00',
      venue: '기숙사체육관',
      isActive: true,
    );

    final event = campaign.toPlannerEvent();

    expect(event.kind, EventKind.homecoming);
    expect(event.start, DateTime(2026, 11, 7, 14, 30));
    expect(event.end, DateTime(2026, 11, 7, 18));
    expect(event.responseEnabled, isFalse);
  });

  test('취소 시각과 사유는 일정 캐시에 보존된다', () {
    final cancelledAt = DateTime(2026, 8, 26, 15, 30);
    final event = LockerEvent(
      id: 'cancelled-event',
      title: '인원 부족 연습',
      start: DateTime(2026, 8, 27, 9),
      end: DateTime(2026, 8, 27, 11),
      place: '71동',
      kind: EventKind.training,
      memo: '',
      cancelledAt: cancelledAt,
      cancellationReason: '인원 부족으로 취소되었습니다.',
    );

    final restored = LockerEvent.fromJson(event.toJson());

    expect(restored.isCancelled, isTrue);
    expect(restored.cancelledAt, cancelledAt);
    expect(restored.cancellationReason, '인원 부족으로 취소되었습니다.');
  });

  test('빠른 터치 드래그의 플링 속도와 연속 가속을 제한한다', () {
    const physics = GentleScrollPhysics();

    expect(physics.maxFlingVelocity, 2400);
    expect(physics.carriedMomentum(20000), lessThanOrEqualTo(1200));
  });

  testWidgets('iOS 기본 뒤로가기는 짧은 드래그를 취소하고 한 번만 화면을 닫는다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const Scaffold(body: Center(child: Text('상세 화면'))),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.timedDragFrom(
      const Offset(5, 400),
      const Offset(70, 0),
      const Duration(milliseconds: 250),
    );
    await tester.pumpAndSettle();
    expect(find.text('상세 화면'), findsOneWidget);

    await tester.timedDragFrom(
      const Offset(5, 400),
      const Offset(300, 0),
      const Duration(milliseconds: 250),
    );
    await tester.pumpAndSettle();
    expect(find.text('상세 화면'), findsNothing);
    expect(find.text('열기'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
