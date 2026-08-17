import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('영상 변경은 영상 상태만 새 객체로 교체한다', () {
    final state = LockerState(isReady: true);

    final next = state.copyWith(likedVideoIds: {'video-1'});

    expect(identical(next.videosState, state.videosState), isFalse);
    expect(identical(next.ui, state.ui), isTrue);
    expect(identical(next.eventsState, state.eventsState), isTrue);
    expect(identical(next.membersState, state.membersState), isTrue);
    expect(identical(next.operationsState, state.operationsState), isTrue);
  });

  test('이벤트 변경은 이벤트 상태만 새 객체로 교체한다', () {
    final state = LockerState(isReady: true);

    final next = state.copyWith(attendance: const {'event-1': '참석'});

    expect(identical(next.eventsState, state.eventsState), isFalse);
    expect(identical(next.ui, state.ui), isTrue);
    expect(identical(next.videosState, state.videosState), isTrue);
    expect(identical(next.membersState, state.membersState), isTrue);
    expect(identical(next.operationsState, state.operationsState), isTrue);
  });

  test('컨트롤러의 영상 좋아요는 영상 상태와 개수만 갱신한다', () async {
    final controller = LockerController.seeded();
    addTearDown(controller.dispose);
    final before = controller.state;
    final video = before.videos.first;

    await controller.toggleVideoLike(video.id);

    final after = controller.state;
    expect(after.likedVideoIds, contains(video.id));
    expect(
      after.videos.firstWhere((item) => item.id == video.id).likeCount,
      video.likeCount + 1,
    );
    expect(identical(after.videosState, before.videosState), isFalse);
    expect(identical(after.eventsState, before.eventsState), isTrue);
    expect(identical(after.membersState, before.membersState), isTrue);
    expect(identical(after.operationsState, before.operationsState), isTrue);
  });
}
