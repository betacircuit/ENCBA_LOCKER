import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기본 릴스가 Instagram 원본의 제목 문구만 사용한다', () {
    final controller = LockerController.seeded();
    addTearDown(controller.dispose);

    final reels = controller.state.videos
        .where((video) => video.sourceType == 'instagram')
        .toList(growable: false);

    expect(reels, hasLength(defaultReelTitlesByShortcode.length));
    for (final reel in reels) {
      final shortcode = Uri.parse(reel.url).pathSegments[1];
      expect(reel.title, defaultReelTitlesByShortcode[shortcode]);
      expect(reel.title, isNot(startsWith('ENCBA REEL ')));
      expect(reel.title, isNot(contains(RegExp(r'[🏀🦾🤞🔥#]'))));
    }
  });
}
