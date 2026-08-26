part of 'supabase_locker_repository.dart';

/// VideosApi - 리포지토리를 테이블·도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin VideosApi on RepoCore {
  @override
  SupabaseClient get _client;

  @override
  String get _userId;

  Future<List<VideoItem>> _loadVideos() async {
    final rows = await _selectVideos(
      (selection) => _client
          .from('videos')
          .select(selection)
          .order('created_at', ascending: false)
          .order('id')
          .limit(videoPageSize),
    );
    final videos = rows.map<VideoItem>(_videoFromRow).toList(growable: false);
    return _attachReviewPlayers(videos);
  }

  Future<VideoItem?> loadVideo(String id) async {
    final rows = await _selectVideos(
      (selection) =>
          _client.from('videos').select(selection).eq('id', id).limit(1),
    );
    if (rows.isEmpty) return null;
    final videos = await _attachReviewPlayers([_videoFromRow(rows.first)]);
    return videos.first;
  }

  /// 링크 테이블이 아직 없는 서버에서는 예전 컬럼만 골라 다시 물어본다.
  Future<List<Map<String, dynamic>>> _selectVideos(
    Future<List<Map<String, dynamic>>> Function(String selection) query,
  ) async {
    try {
      final rows = await query(_videoSelection);
      return rows.map(Map<String, dynamic>.from).toList(growable: false);
    } on PostgrestException catch (error) {
      if (!_isMissingVideoLinkFeature(error)) rethrow;
      debugPrint('Supabase video link migration pending: $error');
      final rows = await query(_legacyVideoSelection);
      return rows.map(Map<String, dynamic>.from).toList(growable: false);
    }
  }

  Future<Set<String>> _loadLikedVideoIds() async {
    final rows = await _client
        .from('video_likes')
        .select('video_id')
        .eq('profile_id', _userId);
    return {for (final row in rows) row['video_id'] as String};
  }

  RealtimeChannel subscribeToVideos(
    void Function(Map<String, dynamic> record) onInsert,
  ) => _client
      .channel('encba-videos-feed')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'videos',
        callback: (payload) => onInsert(payload.newRecord),
      )
      .subscribe();

  Future<void> setVideoLike(String videoId, {required bool liked}) async {
    if (liked) {
      try {
        await _client.from('video_likes').insert({
          'video_id': videoId,
          'profile_id': _userId,
        });
      } on PostgrestException catch (error) {
        if (error.code != '23505') rethrow;
      }
    } else {
      await _client
          .from('video_likes')
          .delete()
          .eq('video_id', videoId)
          .eq('profile_id', _userId);
    }
  }

  Future<VideoItem> addVideo(VideoItem video) async {
    final payload = _videoPayload(video)..['uploaded_by'] = _userId;
    final row = await _writeVideo(
      (values) => _client.from('videos').insert(values).select('id').single(),
      payload,
    );
    final id = row['id'] as String;
    await _syncVideoLinks(id, video.links);
    if (video.category == '복기') {
      await _syncReviewPlayers(id, video.reviewPlayers);
    }
    // 다시 읽지 못하더라도 서버가 매긴 id는 반드시 들고 나가야 상세 화면과
    // 이후 수정이 같은 영상을 가리킨다.
    return await loadVideo(id) ?? video.copyWith(id: id);
  }

  Future<VideoItem> updateVideo(VideoItem video) async {
    await _writeVideo(
      (values) => _client
          .from('videos')
          .update(values)
          .eq('id', video.id)
          .select('id')
          .single(),
      _videoPayload(video),
    );
    await _syncVideoLinks(video.id, video.links);
    if (video.category == '복기') {
      await _syncReviewPlayers(video.id, video.reviewPlayers);
    }
    return await loadVideo(video.id) ?? video;
  }

  Map<String, dynamic> _videoPayload(VideoItem video) => {
    'title': video.title,
    'category': _videoCategoryToDatabase(video.category),
    'source_url': video.url,
    'youtube_id': video.youtubeId.isEmpty ? null : video.youtubeId,
    'source_type': video.sourceType,
    // 예전 앱과 예전 서버를 위해 앞 네 쿼터는 컬럼에도 그대로 남긴다.
    'quarter_1_url': video.quarterUrls.elementAtOrNull(0),
    'quarter_2_url': video.quarterUrls.elementAtOrNull(1),
    'quarter_3_url': video.quarterUrls.elementAtOrNull(2),
    'quarter_4_url': video.quarterUrls.elementAtOrNull(3),
    'audience_type': video.audienceType,
    'audience_values': video.audienceValues,
    'duration_seconds': _durationToSeconds(video.durationLabel),
    'recorded_on': video.recordedOn == null
        ? null
        : _dateOnly(video.recordedOn!),
  };

  /// recorded_on이 없는 서버에서는 그 값만 빼고 다시 저장한다.
  Future<Map<String, dynamic>> _writeVideo(
    Future<Map<String, dynamic>> Function(Map<String, dynamic> values) write,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await write(payload);
    } on PostgrestException catch (error) {
      if (!_isMissingVideoLinkFeature(error)) rethrow;
      debugPrint('Supabase video link migration pending: $error');
      return write(Map<String, dynamic>.from(payload)..remove('recorded_on'));
    }
  }

  Future<void> _syncVideoLinks(String videoId, List<VideoLink> links) async {
    try {
      await _client.rpc(
        'set_video_links',
        params: {
          'requested_video_id': videoId,
          'requested_links': [
            for (final link in links)
              {'quarter': link.quarterNumber, 'url': link.url},
          ],
        },
      );
    } on PostgrestException catch (error) {
      if (!_isMissingVideoLinkFeature(error)) rethrow;
      debugPrint('Supabase video link migration pending: $error');
    }
  }

  Future<void> deleteVideo(String id) =>
      _client.from('videos').delete().eq('id', id);

  static const _commentSelection =
      'id,video_id,profile_id,quarter_number,link_id,timestamp_seconds,'
      'end_timestamp_seconds,body,created_at,'
      'profiles!video_comments_profile_id_fkey(name)';

  static const _commentSelectionWithoutRange =
      'id,video_id,profile_id,quarter_number,link_id,timestamp_seconds,body,created_at,'
      'profiles!video_comments_profile_id_fkey(name)';

  static const _legacyCommentSelection =
      'id,video_id,profile_id,quarter_number,timestamp_seconds,body,created_at,'
      'profiles!video_comments_profile_id_fkey(name)';

  Future<List<VideoCommentItem>> loadVideoComments(String videoId) async {
    Future<List<Map<String, dynamic>>> query(String selection) async {
      final rows = await _client
          .from('video_comments')
          .select(selection)
          .eq('video_id', videoId)
          .order('timestamp_seconds')
          .order('created_at');
      return rows.map(Map<String, dynamic>.from).toList(growable: false);
    }

    Future<List<Map<String, dynamic>>> queryWithoutRange() async {
      try {
        return await query(_commentSelectionWithoutRange);
      } on PostgrestException catch (error) {
        if (!_isMissingVideoLinkFeature(error)) rethrow;
        return query(_legacyCommentSelection);
      }
    }

    List<Map<String, dynamic>> rows;
    try {
      rows = await query(_commentSelection);
    } on PostgrestException catch (error) {
      if (_isMissingVideoCommentRangeFeature(error)) {
        rows = await queryWithoutRange();
      } else if (_isMissingVideoLinkFeature(error)) {
        rows = await query(_legacyCommentSelection);
      } else {
        rethrow;
      }
    }
    final comments = rows.map(_videoCommentFromRow).toList(growable: false);
    return _attachCommentTargets(videoId, comments);
  }

  Future<VideoCommentItem> addVideoComment({
    required String videoId,
    required int? quarterNumber,
    required int? linkId,
    required int timestampSeconds,
    int? endTimestampSeconds,
    required String body,
    List<VideoTaggedMember> targetPlayers = const [],
  }) async {
    // 값이 없는 컬럼은 아예 보내지 않는다. 릴스(하이라이트)처럼 쿼터·링크가
    // 없는 댓글에서 명시적 null이 원인일 수 있는 저장 실패를 줄인다.
    final payload = <String, dynamic>{
      'video_id': videoId,
      'profile_id': _userId,
      'quarter_number': quarterNumber,
      'link_id': linkId,
      'timestamp_seconds': timestampSeconds,
      'end_timestamp_seconds': endTimestampSeconds,
      'body': body,
    };
    Future<Map<String, dynamic>> insert(
      Map<String, dynamic> insertPayload,
      String selection,
    ) => _client
        .from('video_comments')
        .insert(insertPayload)
        .select(selection)
        .single();

    Future<Map<String, dynamic>> insertWithoutRange() async {
      final fallbackPayload = Map<String, dynamic>.from(payload)
        ..remove('end_timestamp_seconds');
      try {
        return await insert(fallbackPayload, _commentSelectionWithoutRange);
      } on PostgrestException catch (error) {
        if (!_isMissingVideoLinkFeature(error)) rethrow;
        fallbackPayload.remove('link_id');
        return insert(fallbackPayload, _legacyCommentSelection);
      }
    }

    Map<String, dynamic> row;
    try {
      row = await insert(payload, _commentSelection);
    } on PostgrestException catch (error) {
      if (_isMissingVideoCommentRangeFeature(error)) {
        row = await insertWithoutRange();
      } else if (_isMissingVideoLinkFeature(error)) {
        row = await insert(
          Map<String, dynamic>.from(payload)
            ..remove('end_timestamp_seconds')
            ..remove('link_id'),
          _legacyCommentSelection,
        );
      } else {
        rethrow;
      }
    }
    final saved = _videoCommentFromRow(Map<String, dynamic>.from(row));
    await _syncCommentTargets(saved.id, targetPlayers);
    return VideoCommentItem(
      id: saved.id,
      videoId: saved.videoId,
      profileId: saved.profileId,
      timestampSeconds: saved.timestampSeconds,
      body: saved.body,
      author: saved.author,
      createdAt: saved.createdAt,
      quarterNumber: saved.quarterNumber,
      linkId: saved.linkId ?? linkId,
      endTimestampSeconds: saved.endTimestampSeconds ?? endTimestampSeconds,
      targetPlayers: targetPlayers,
    );
  }

  Future<List<VideoItem>> _attachReviewPlayers(List<VideoItem> videos) async {
    final reviewIds = videos
        .where((video) => video.category == '복기')
        .map((video) => video.id)
        .toList(growable: false);
    if (reviewIds.isEmpty) return videos;
    final rows = await _orFallback<dynamic>(
      _client.rpc(
        'list_video_review_players',
        params: {'requested_video_ids': reviewIds},
      ),
      const <dynamic>[],
      debugLabel: 'video review players',
    );
    final playersByVideo = <String, List<VideoTaggedMember>>{};
    for (final raw in rows as List<dynamic>) {
      final row = Map<String, dynamic>.from(raw as Map);
      playersByVideo
          .putIfAbsent(row['video_id'] as String, () => [])
          .add(
            VideoTaggedMember(
              directoryId: row['directory_id'] as String,
              name: row['name'] as String,
              studentYear: _databaseInt(row['student_year']),
              jerseyNumber: _databaseInt(row['jersey_number']),
            ),
          );
    }
    return videos
        .map(
          (video) => video.copyWith(
            reviewPlayers:
                playersByVideo[video.id] ?? const <VideoTaggedMember>[],
          ),
        )
        .toList(growable: false);
  }

  Future<List<VideoCommentItem>> _attachCommentTargets(
    String videoId,
    List<VideoCommentItem> comments,
  ) async {
    if (comments.isEmpty) return comments;
    final rows = await _orFallback<dynamic>(
      _client.rpc(
        'list_video_comment_targets',
        params: {'requested_video_id': videoId},
      ),
      const <dynamic>[],
      debugLabel: 'video comment targets',
    );
    final targetsByComment = <int, List<VideoTaggedMember>>{};
    for (final raw in rows as List<dynamic>) {
      final row = Map<String, dynamic>.from(raw as Map);
      targetsByComment
          .putIfAbsent((row['comment_id'] as num).toInt(), () => [])
          .add(
            VideoTaggedMember(
              directoryId: row['directory_id'] as String,
              name: row['name'] as String,
              studentYear: _databaseInt(row['student_year']),
              jerseyNumber: _databaseInt(row['jersey_number']),
            ),
          );
    }
    return comments
        .map(
          (comment) => VideoCommentItem(
            id: comment.id,
            videoId: comment.videoId,
            profileId: comment.profileId,
            timestampSeconds: comment.timestampSeconds,
            body: comment.body,
            author: comment.author,
            createdAt: comment.createdAt,
            quarterNumber: comment.quarterNumber,
            linkId: comment.linkId,
            endTimestampSeconds: comment.endTimestampSeconds,
            targetPlayers:
                targetsByComment[comment.id] ?? const <VideoTaggedMember>[],
          ),
        )
        .toList(growable: false);
  }

  Future<void> _syncReviewPlayers(
    String videoId,
    List<VideoTaggedMember> players,
  ) async {
    try {
      await _client.rpc(
        'set_video_review_players',
        params: {
          'requested_video_id': videoId,
          'requested_directory_ids': players
              .map((player) => player.directoryId)
              .toList(growable: false),
        },
      );
    } on PostgrestException catch (error) {
      if (!_isMissingVideoPlayerFeature(error)) rethrow;
      debugPrint('Supabase video review player migration pending: $error');
    }
  }

  Future<void> _syncCommentTargets(
    int commentId,
    List<VideoTaggedMember> players,
  ) async {
    try {
      await _client.rpc(
        'set_video_comment_targets',
        params: {
          'requested_comment_id': commentId,
          'requested_directory_ids': players
              .map((player) => player.directoryId)
              .toList(growable: false),
        },
      );
    } on PostgrestException catch (error) {
      if (!_isMissingVideoPlayerFeature(error)) rethrow;
      debugPrint('Supabase video comment target migration pending: $error');
    }
  }

  Future<void> deleteVideoComment(int id) =>
      _client.from('video_comments').delete().eq('id', id);

  VideoCommentItem _videoCommentFromRow(Map<String, dynamic> row) {
    final profile = row['profiles'] as Map?;
    return VideoCommentItem(
      id: row['id'] as int,
      videoId: row['video_id'] as String,
      profileId: row['profile_id'] as String,
      quarterNumber: row['quarter_number'] as int?,
      linkId: _databaseInt(row['link_id']),
      timestampSeconds: row['timestamp_seconds'] as int? ?? 0,
      endTimestampSeconds: _databaseInt(row['end_timestamp_seconds']),
      body: row['body'] as String,
      author: profile?['name'] as String? ?? 'ENCBA',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  /// 링크 테이블 값을 우선 쓰고, 아직 없는 서버에서는 쿼터 컬럼으로 되돌아간다.
  List<VideoLink> _videoLinksFromRow(Map<String, dynamic> row) {
    final rows = row['video_links'] as List?;
    if (rows != null) {
      final links = rows.map((raw) {
        final link = Map<String, dynamic>.from(raw as Map);
        return (
          sort: _databaseInt(link['sort_order']) ?? 0,
          link: VideoLink(
            id: _databaseInt(link['id']),
            quarterNumber: _databaseInt(link['quarter_number']),
            url: link['url'] as String,
          ),
        );
      }).toList()..sort((a, b) => a.sort.compareTo(b.sort));
      return sortedVideoLinks(links.map((entry) => entry.link));
    }
    return [
      for (final (index, key) in const [
        'quarter_1_url',
        'quarter_2_url',
        'quarter_3_url',
        'quarter_4_url',
      ].indexed)
        if (row[key] is String && (row[key] as String).isNotEmpty)
          VideoLink(url: row[key] as String, quarterNumber: index + 1),
    ];
  }

  VideoItem _videoFromRow(Map<String, dynamic> row) {
    final uploader = row['profiles'] as Map?;
    return VideoItem(
      id: row['id'] as String,
      title: row['title'] as String,
      durationLabel: _formatDuration(_databaseInt(row['duration_seconds'])),
      category: _videoCategoryFromDatabase(row['category'] as String),
      url: row['source_url'] as String,
      youtubeId: row['youtube_id'] as String? ?? '',
      uploadedAt: DateTime.parse(row['created_at'] as String).toLocal(),
      uploader:
          uploader?['name'] as String? ??
          uploader?['display_name'] as String? ??
          'ENCBA',
      accent: 0xFF00539B,
      likeCount: _databaseInt(row['like_count']) ?? 0,
      sourceType: row['source_type'] as String? ?? 'youtube',
      links: _videoLinksFromRow(row),
      recordedOn: row['recorded_on'] == null
          ? null
          : DateTime.parse(row['recorded_on'] as String),
      audienceType: row['audience_type'] as String? ?? 'all',
      audienceValues: List<String>.from(
        row['audience_values'] as List? ?? const [],
      ),
    );
  }
}
