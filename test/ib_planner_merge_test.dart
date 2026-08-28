import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:flutter_test/flutter_test.dart';

OperationAssignment _assignment({
  required String id,
  required String title,
  required String assignee,
  int day = 3,
  bool isMine = false,
  String location = '',
}) => OperationAssignment(
  id: id,
  title: title,
  start: DateTime(2026, 5, day, 13),
  end: DateTime(2026, 5, day, 14),
  location: location,
  memo: 'IB 리그 운영 · 5월 $day일',
  assigneeName: assignee,
  isMine: isMine,
);

void main() {
  test('같은 역할·시간에 배정된 사람이 여럿이어도 일정은 하나만 만든다', () {
    final merged = mergedOperationPlannerEvents([
      _assignment(id: 'a1', title: '1경기 운영 A', assignee: '김민수'),
      _assignment(id: 'a2', title: '1경기 운영 A', assignee: '이준호'),
      _assignment(id: 'a3', title: '1경기 운영 A', assignee: '박서준'),
      _assignment(id: 'b1', title: '1경기 운영 B', assignee: '최지우'),
    ]);

    expect(merged.length, 2);
    expect(
      merged.map((event) => event.title).toSet(),
      {'1경기 운영 A', '1경기 운영 B'},
    );
    final roleA = merged.firstWhere((event) => event.title == '1경기 운영 A');
    expect(roleA.memo, contains('담당 3명'));
    expect(roleA.memo, contains('김민수'));
    expect(roleA.memo, contains('박서준'));
  });

  test('IB 운영 장소가 비어 있어도 종합체육관으로 채운다', () {
    final merged = mergedOperationPlannerEvents([
      _assignment(id: 'a1', title: '2경기 운영 A', assignee: '김민수'),
    ]);

    expect(merged.single.place, ibOperationVenue);
  });

  test('묶인 일정은 내 배정을 대표로 삼는다', () {
    final merged = mergedOperationPlannerEvents([
      _assignment(id: 'zzz-other', title: '3경기 심판', assignee: '이준호'),
      _assignment(
        id: 'aaa-mine',
        title: '3경기 심판',
        assignee: '김민수',
        isMine: true,
      ),
    ]);

    expect(merged.single.id, 'operation-aaa-mine');
  });

  test('플래너 목록에 보이는 IB 일정은 상세에서도 같은 ID로 찾을 수 있다', () {
    final state = LockerState(
      isReady: true,
      operations: [
        _assignment(id: 'mine', title: '1경기 운영 A', assignee: '나', isMine: true),
      ],
      allOperations: [
        _assignment(id: 'other-1', title: '1경기 운영 B', assignee: '김민수'),
      ],
    );

    final listed = state.plannerEvents;
    // 남의 배정은 플래너에 끼지 않는다.
    expect(listed.map((event) => event.id), ['operation-mine']);
    // 화면이 목록과 상세에서 같은 집합을 쓰는지 확인한다. 예전에는 상세가
    // 목록과 다른 목록을 뒤져서 일정을 열 수 없었다.
    final resolved = state.eventsState
        .plannerEventsWith(state.operationsState)
        .where((event) => event.id == listed.single.id);
    expect(resolved, isNotEmpty);
  });
}
