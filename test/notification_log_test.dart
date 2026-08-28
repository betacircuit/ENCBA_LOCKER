import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 알림 기록의 항목 이름을 한국어로 읽는다', () {
    NotificationLogEntry entry(String category) => NotificationLogEntry(
      id: 'n1',
      recipientName: '김민수',
      category: category,
      title: '제목',
      body: '',
      createdAt: DateTime(2026, 8, 30),
    );

    expect(entry('announcements').categoryLabel, '공지');
    expect(entry('events').categoryLabel, '일정');
    expect(entry('videos').categoryLabel, '영상');
    // 모르는 값이 와도 화면이 비지 않게 기본 이름을 준다.
    expect(entry('unknown').categoryLabel, '알림');
  });

  test('빈 route는 null로 읽어 눌러도 아무 데도 가지 않게 한다', () {
    final row = {
      'id': 'n1',
      'profile_id': null,
      'recipient_name': '전체',
      'category': 'announcements',
      'title': '공지',
      'body': '',
      'route': '   ',
      'created_at': '2026-08-30T00:00:00.000Z',
    };

    expect(NotificationLogEntry.fromRow(row).route, isNull);
    expect(
      NotificationLogEntry.fromRow({...row, 'route': '/announcements/a1'}).route,
      '/announcements/a1',
    );
  });

  test('받는 사람이 비어 있으면 전체 발송으로 읽는다', () {
    final entry = NotificationLogEntry.fromRow({
      'id': 'n1',
      'profile_id': null,
      'recipient_name': null,
      'category': 'events',
      'title': '새 일정',
      'body': '',
      'route': null,
      'created_at': '2026-08-30T00:00:00.000Z',
    });

    expect(entry.recipientName, '전체');
    expect(entry.profileId, isNull);
  });
}
