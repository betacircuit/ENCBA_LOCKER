import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/locker/data/supabase_locker_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('일정 조회 기준일은 기기 시간대와 무관하게 한국 자정으로 고정된다', () {
    expect(
      encbaDayStartsAtUtc(DateTime.parse('2026-08-20T00:30:00+09:00')),
      DateTime.utc(2026, 8, 19, 15),
    );
    expect(
      encbaDayStartsAtUtc(DateTime.parse('2026-08-19T17:00:00-07:00')),
      DateTime.utc(2026, 8, 19, 15),
    );
  });

  test('영상 ID 조회는 서버 행을 도메인 모델로 변환한다', () async {
    final httpClient = MockClient((request) async {
      expect(request.url.path, '/rest/v1/videos');
      expect(request.url.queryParameters['id'], 'eq.video-1');
      return http.Response(
        jsonEncode([
          {
            'id': 'video-1',
            'title': '픽앤롤 읽기',
            'category': 'shared',
            'source_url': 'https://youtu.be/M7lc1UVf-VE',
            'youtube_id': 'M7lc1UVf-VE',
            'source_type': 'youtube',
            'quarter_1_url': null,
            'quarter_2_url': null,
            'quarter_3_url': null,
            'quarter_4_url': null,
            'audience_type': 'all',
            'audience_values': <String>[],
            'duration_seconds': 125,
            'created_at': '2026-08-17T03:00:00.000Z',
            'like_count': 4,
            'profiles': {'name': '김민수', 'display_name': '김민수'},
          },
        ]),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: httpClient,
    );
    addTearDown(client.dispose);
    final repository = SupabaseLockerRepository(client, LocalStore());

    final video = await repository.loadVideo('video-1');

    expect(video, isNotNull);
    expect(video!.title, '픽앤롤 읽기');
    expect(video.category, '공유');
    expect(video.durationLabel, '2:05');
    expect(video.uploader, '김민수');
    expect(video.likeCount, 4);
  });

  test('댓글 삭제는 해당 댓글 ID만 DELETE 요청한다', () async {
    final httpClient = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/rest/v1/video_comments');
      expect(request.url.queryParameters['id'], 'eq.17');
      return http.Response('', 204, request: request);
    });
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: httpClient,
    );
    addTearDown(client.dispose);
    final repository = SupabaseLockerRepository(client, LocalStore());

    await repository.deleteVideoComment(17);
  });

  test('하이라이트 댓글은 빈 선택 컬럼과 피드백 RPC 없이 한 번만 저장한다', () async {
    const userId = 'ca71127f-4a64-4d1d-bbab-0d6b830bc2d6';
    var requestCount = 0;
    final httpClient = MockClient((request) async {
      requestCount += 1;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/video_comments');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body, {
        'video_id': 'highlight-1',
        'profile_id': userId,
        'timestamp_seconds': 0,
        'body': '좋아요',
      });
      return http.Response(
        jsonEncode({
          'id': 18,
          'video_id': 'highlight-1',
          'profile_id': userId,
          'quarter_number': null,
          'link_id': null,
          'timestamp_seconds': 0,
          'end_timestamp_seconds': null,
          'body': '좋아요',
          'created_at': '2026-08-26T04:00:00.000Z',
          'profiles': {'name': '김민수'},
        }),
        201,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: httpClient,
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': _testJwt(userId),
        'token_type': 'bearer',
        'refresh_token': 'test-refresh-token',
        'expires_in': 3600,
        'user': {
          'id': userId,
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-08-01T00:00:00.000Z',
        },
      }),
    );
    final repository = SupabaseLockerRepository(client, LocalStore());

    final saved = await repository.addVideoComment(
      videoId: 'highlight-1',
      quarterNumber: null,
      linkId: null,
      timestampSeconds: 0,
      body: '좋아요',
    );

    expect(saved.id, 18);
    expect(saved.profileId, userId);
    expect(requestCount, 1);
  });

  test('홈커밍 연락망은 원자적 교체 RPC 한 번으로 전송한다', () async {
    final httpClient = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/import_homecoming_contacts');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['requested_campaign_id'], 'campaign-1');
      expect(body['requested_file_name'], '2026-2 홈커밍.xlsx');
      expect(body['requested_contacts'], [
        {
          'source_row': 4,
          'senior_name': '김엔크바',
          'phone': '',
          'contact_status': 'pending',
        },
      ]);
      return http.Response(
        jsonEncode({
          'imported': 1,
          'missing_phones': 1,
          'unmatched_assignees': 0,
        }),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: httpClient,
    );
    addTearDown(client.dispose);
    final repository = SupabaseLockerRepository(client, LocalStore());

    await repository.importHomecomingContacts(
      campaignId: 'campaign-1',
      fileName: '2026-2 홈커밍.xlsx',
      contacts: const [
        {
          'source_row': 4,
          'senior_name': '김엔크바',
          'phone': '',
          'contact_status': 'pending',
        },
      ],
    );
  });
}

String _testJwt(String userId) {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'sub': userId, 'aud': 'authenticated', 'exp': 4102444800})}.'
      'test-signature';
}
