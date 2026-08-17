import 'dart:convert';

import 'package:encba_locker/core/config/app_config.dart';
import 'package:http/http.dart' as http;

class YoutubeThumbnailService {
  YoutubeThumbnailService({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ?? AppConfig.youtubeApiKey;

  static final instance = YoutubeThumbnailService();

  final http.Client _client;
  final String _apiKey;
  final Map<String, Future<String?>> _cache = {};

  Future<String?> load(String videoId) {
    if (_apiKey.isEmpty || videoId.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(videoId, () => _fetch(videoId));
  }

  Future<String?> _fetch(String videoId) async {
    try {
      final response = await _client
          .get(
            Uri.https('www.googleapis.com', '/youtube/v3/videos', {
              'part': 'snippet',
              'id': videoId,
              'key': _apiKey,
            }),
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      return youtubeThumbnailUrlFromPayload(payload);
    } on Object {
      return null;
    }
  }
}

String? youtubeThumbnailUrlFromPayload(Object? payload) {
  if (payload is! Map) return null;
  final items = payload['items'];
  if (items is! List || items.isEmpty || items.first is! Map) return null;
  final snippet = (items.first as Map)['snippet'];
  if (snippet is! Map) return null;
  final thumbnails = snippet['thumbnails'];
  if (thumbnails is! Map) return null;
  for (final quality in const [
    'maxres',
    'standard',
    'high',
    'medium',
    'default',
  ]) {
    final candidate = thumbnails[quality];
    if (candidate is Map && candidate['url'] is String) {
      final url = candidate['url'] as String;
      if (Uri.tryParse(url)?.scheme == 'https') return url;
    }
  }
  return null;
}
