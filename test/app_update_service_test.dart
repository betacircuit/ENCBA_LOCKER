import 'dart:convert';

import 'package:encba_locker/features/locker/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('커밋 메시지의 첫 줄만 요약으로 쓴다', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode([
          {
            'sha': 'abcdef1234567890',
            'commit': {
              'message': 'fix(locker): 뒤로가기 고침\n\n본문은 길어서 목록에 담지 않는다.',
              'author': {'name': 'CHOIJAEWON', 'date': '2026-08-29T01:00:00Z'},
            },
          },
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final entries = await AppUpdateService(client: client).loadRecent();

    expect(entries, hasLength(1));
    expect(entries.single.summary, 'fix(locker): 뒤로가기 고침');
    expect(entries.single.shortSha, 'abcdef1');
    expect(entries.single.author, 'CHOIJAEWON');
  });

  test('형식이 깨진 항목은 건너뛰고 나머지를 읽는다', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode([
          {'sha': 'no-commit-field'},
          {
            'sha': 'aaaaaaa1111111',
            'commit': {
              'message': '',
              'author': {'name': '', 'date': '2026-08-29T02:00:00Z'},
            },
          },
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final entries = await AppUpdateService(client: client).loadRecent();

    expect(entries, hasLength(1));
    // 메시지가 비어 있어도 목록이 비지 않게 자리를 채운다.
    expect(entries.single.summary, '(메시지 없음)');
  });

  test('조회 한도(403)는 이유를 알려 준다', () async {
    final client = MockClient((request) async => http.Response('{}', 403));

    expect(
      () => AppUpdateService(client: client).loadRecent(),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.message,
          'message',
          contains('한도'),
        ),
      ),
    );
  });
}
