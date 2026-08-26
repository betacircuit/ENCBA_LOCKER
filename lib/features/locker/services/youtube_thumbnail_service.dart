import 'dart:convert';

import 'package:encba_locker/core/config/app_config.dart';
import 'package:http/http.dart' as http;

class YoutubeVideoMetadata {
  const YoutubeVideoMetadata({this.thumbnailUrl, this.durationSeconds});

  final String? thumbnailUrl;
  final int? durationSeconds;
}

class YoutubeThumbnailService {
  YoutubeThumbnailService({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ?? AppConfig.youtubeApiKey;

  static final instance = YoutubeThumbnailService();

  final http.Client _client;
  final String _apiKey;
  final Map<String, Future<YoutubeVideoMetadata?>> _cache = {};

  Future<String?> load(String videoId) async {
    final metadata = await loadMetadata(videoId);
    return metadata?.thumbnailUrl;
  }

  Future<YoutubeVideoMetadata?> loadMetadata(String videoId) {
    if (_apiKey.isEmpty || videoId.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(videoId, () => _fetchMetadata(videoId));
  }

  Future<YoutubeVideoMetadata?> _fetchMetadata(String videoId) async {
    try {
      final response = await _client
          .get(
            Uri.https('www.googleapis.com', '/youtube/v3/videos', {
              'part': 'snippet,contentDetails',
              'id': videoId,
              'key': _apiKey,
            }),
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      return youtubeVideoMetadataFromPayload(payload);
    } on Object {
      return null;
    }
  }
}

String? youtubeThumbnailUrlFromPayload(Object? payload) {
  final item = _firstVideoItem(payload);
  if (item == null) return null;
  final snippet = item['snippet'];
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

YoutubeVideoMetadata? youtubeVideoMetadataFromPayload(Object? payload) {
  final item = _firstVideoItem(payload);
  if (item == null) return null;
  final contentDetails = item['contentDetails'];
  final duration = contentDetails is Map ? contentDetails['duration'] : null;
  return YoutubeVideoMetadata(
    thumbnailUrl: youtubeThumbnailUrlFromPayload(payload),
    durationSeconds: duration is String
        ? youtubeDurationSeconds(duration)
        : null,
  );
}

int? youtubeDurationSeconds(String? value) {
  if (value == null) return null;
  final match = RegExp(
    r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$',
  ).firstMatch(value);
  if (match == null || match.groups([1, 2, 3]).every((part) => part == null)) {
    return null;
  }
  final hours = int.tryParse(match.group(1) ?? '0');
  final minutes = int.tryParse(match.group(2) ?? '0');
  final seconds = int.tryParse(match.group(3) ?? '0');
  if (hours == null || minutes == null || seconds == null) return null;
  return hours * 3600 + minutes * 60 + seconds;
}

String formatVideoDurationLabel(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

int? parseVideoDurationLabel(String value) {
  final parts = value.trim().split(':').map(int.tryParse).toList();
  if (parts.length != 2 || parts.any((item) => item == null)) return null;
  final minutes = parts[0]!;
  final seconds = parts[1]!;
  if (minutes < 0 || seconds < 0 || seconds >= 60) return null;
  return minutes * 60 + seconds;
}

Map? _firstVideoItem(Object? payload) {
  if (payload is! Map) return null;
  final items = payload['items'];
  if (items is! List || items.isEmpty || items.first is! Map) return null;
  return items.first as Map;
}
