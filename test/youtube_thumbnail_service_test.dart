import 'dart:convert';

import 'package:encba_locker/features/locker/services/youtube_thumbnail_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  test('YouTube metadata에서 썸네일과 재생 시간을 함께 읽는다', () {
    final metadata = youtubeVideoMetadataFromPayload({
      'items': [
        {
          'snippet': {
            'thumbnails': {
              'high': {'url': 'https://example.com/high.jpg'},
            },
          },
          'contentDetails': {'duration': 'PT8M24S'},
        },
      ],
    });

    expect(metadata?.thumbnailUrl, 'https://example.com/high.jpg');
    expect(metadata?.durationSeconds, 504);
  });

  test('ISO-8601 YouTube 재생 시간을 초로 변환한다', () {
    expect(youtubeDurationSeconds('PT8M24S'), 504);
    expect(youtubeDurationSeconds('PT1H2M3S'), 3723);
    expect(youtubeDurationSeconds('PT45S'), 45);
  });

  test('자동 재생 시간을 저장 형식으로 왕복 변환한다', () {
    expect(formatVideoDurationLabel(504), '8:24');
    expect(formatVideoDurationLabel(3723), '62:03');
    expect(parseVideoDurationLabel('8:24'), 504);
    expect(parseVideoDurationLabel('62:03'), 3723);
    expect(parseVideoDurationLabel('8:75'), isNull);
  });

  test('잘못됐거나 누락된 재생 시간은 null이다', () {
    expect(youtubeDurationSeconds(null), isNull);
    expect(youtubeDurationSeconds(''), isNull);
    expect(youtubeDurationSeconds('PT'), isNull);
    expect(youtubeDurationSeconds('8:24'), isNull);
    expect(
      youtubeVideoMetadataFromPayload({
        'items': [
          {'snippet': <String, Object?>{}},
        ],
      })?.durationSeconds,
      isNull,
    );
  });

  test('metadata와 기존 thumbnail load는 같은 API 요청을 공유한다', () async {
    var requestCount = 0;
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestCount++;
      requestedUri = request.url;
      return http.Response(
        jsonEncode({
          'items': [
            {
              'snippet': {
                'thumbnails': {
                  'maxres': {'url': 'https://example.com/maxres.jpg'},
                },
              },
              'contentDetails': {'duration': 'PT45S'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final service = YoutubeThumbnailService(client: client, apiKey: 'test-key');

    final results = await Future.wait<Object?>([
      service.load('video-1'),
      service.loadMetadata('video-1'),
    ]);

    expect(requestCount, 1);
    expect(requestedUri.path, '/youtube/v3/videos');
    expect(requestedUri.queryParameters['part'], 'snippet,contentDetails');
    expect(requestedUri.queryParameters['id'], 'video-1');
    expect(requestedUri.queryParameters['key'], 'test-key');
    expect(results.first, 'https://example.com/maxres.jpg');
    final metadata = results.last as YoutubeVideoMetadata?;
    expect(metadata?.durationSeconds, 45);
  });
}
