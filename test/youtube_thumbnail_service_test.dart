import 'package:encba_locker/features/locker/services/youtube_thumbnail_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('YouTube API 응답에서 가장 높은 화질의 공식 썸네일을 고른다', () {
    final url = youtubeThumbnailUrlFromPayload({
      'items': [
        {
          'snippet': {
            'thumbnails': {
              'high': {'url': 'https://example.com/high.jpg'},
              'maxres': {'url': 'https://example.com/maxres.jpg'},
            },
          },
        },
      ],
    });

    expect(url, 'https://example.com/maxres.jpg');
  });

  test('영상이 없거나 HTTPS 썸네일이 아니면 fallback을 사용한다', () {
    expect(youtubeThumbnailUrlFromPayload({'items': []}), isNull);
    expect(
      youtubeThumbnailUrlFromPayload({
        'items': [
          {
            'snippet': {
              'thumbnails': {
                'high': {'url': 'http://example.com/high.jpg'},
              },
            },
          },
        ],
      }),
      isNull,
    );
  });
}
