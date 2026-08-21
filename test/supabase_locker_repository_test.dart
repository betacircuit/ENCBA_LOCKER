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
