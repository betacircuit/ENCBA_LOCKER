import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 배포된 변경 한 건.
@immutable
class AppUpdateEntry {
  const AppUpdateEntry({
    required this.sha,
    required this.summary,
    required this.author,
    required this.committedAt,
  });

  final String sha;

  /// 커밋 메시지의 첫 줄. 본문은 길어서 목록에 담지 않는다.
  final String summary;
  final String author;
  final DateTime committedAt;

  String get shortSha => sha.length <= 7 ? sha : sha.substring(0, 7);
}

/// GitHub에서 최근 배포 내역을 읽어 온다.
///
/// 저장소가 공개라 토큰 없이 읽을 수 있다. 관리자가 가끔 열어 보는
/// 화면이라 시간당 60회 제한에도 넉넉하다.
class AppUpdateService {
  AppUpdateService({http.Client? client, String? repository})
    : _client = client ?? http.Client(),
      _repository = repository ?? defaultRepository;

  final http.Client _client;
  final String _repository;

  static const defaultRepository = 'betacircuit/ENCBA_LOCKER';

  Future<List<AppUpdateEntry>> loadRecent({int limit = 20}) async {
    final uri = Uri.https('api.github.com', '/repos/$_repository/commits', {
      'per_page': '$limit',
    });
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode != 200) {
      throw AppUpdateException(
        response.statusCode == 403
            ? '깃허브 조회 한도를 넘었습니다. 잠시 뒤 다시 열어 주세요.'
            : '배포 내역을 불러오지 못했습니다.',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const AppUpdateException('배포 내역을 읽지 못했습니다.');
    }
    return [
      for (final raw in decoded)
        if (_entryFrom(raw) case final AppUpdateEntry entry) entry,
    ];
  }

  AppUpdateEntry? _entryFrom(Object? raw) {
    if (raw is! Map) return null;
    final sha = raw['sha'];
    final commit = raw['commit'];
    if (sha is! String || commit is! Map) return null;
    final author = commit['author'];
    final date = author is Map ? author['date'] : null;
    final committedAt = DateTime.tryParse(date is String ? date : '');
    if (committedAt == null) return null;
    final message = commit['message'];
    final summary = message is String && message.trim().isNotEmpty
        ? message.trim().split('\n').first
        : '(메시지 없음)';
    return AppUpdateEntry(
      sha: sha,
      summary: summary,
      author: author is Map ? (author['name'] as String? ?? '') : '',
      committedAt: committedAt.toLocal(),
    );
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}
