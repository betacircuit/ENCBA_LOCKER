part of 'supabase_locker_repository.dart';

/// ContentApi - 리포지토리를 테이블·도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin ContentApi on RepoCore {
  @override
  SupabaseClient get _client;

  @override
  String get _userId;

  Future<List<AnnouncementItem>> loadAnnouncements() async {
    final rows = await _selectAnnouncementRows(
      (selection) => _client
          .from('announcements')
          .select(selection)
          .order('pinned', ascending: false)
          .order('published_at', ascending: false)
          .limit(50),
    );
    return rows.map(_announcementFromRow).toList();
  }

  Future<AnnouncementItem?> loadAnnouncement(String id) async {
    final rows = await _selectAnnouncementRows(
      (selection) =>
          _client.from('announcements').select(selection).eq('id', id).limit(1),
    );
    if (rows.isEmpty) return null;
    return _announcementFromRow(rows.first);
  }

  Future<AnnouncementItem> addAnnouncement({
    required String title,
    required String body,
    required bool pinned,
    required bool isUrgent,
    List<String> linkedEventIds = const [],
    String? imageBase64,
    String? imageName,
    List<String> pollOptions = const [],
    String pollQuestion = '',
  }) async {
    String? uploadedPath;
    String? imageUrl;
    if (imageBase64 != null) {
      final uploaded = await _uploadAnnouncementImage(imageBase64, imageName);
      uploadedPath = uploaded.path;
      imageUrl = uploaded.url;
    }
    final payload = <String, dynamic>{
      'title': title,
      'body': body,
      'pinned': pinned,
      'is_urgent': isUrgent,
      'image_url': imageUrl,
      'poll_options': pollOptions,
      'poll_question': pollQuestion,
      'created_by': _userId,
      'updated_by': _userId,
    };
    final Map<String, dynamic> row;
    try {
      row = await _writeAnnouncement(
        () => _client
            .from('announcements')
            .insert(payload)
            .select(_announcementSelection)
            .single(),
        () => _client
            .from('announcements')
            .insert(
              Map<String, dynamic>.from(payload)
                ..remove('is_urgent')
                ..remove('image_url')
                ..remove('poll_options')
                ..remove('poll_question'),
            )
            .select(_legacyAnnouncementSelection)
            .single(),
        requiresCurrentSchema:
            imageBase64 != null ||
            pollOptions.isNotEmpty ||
            pollQuestion.trim().isNotEmpty,
      );
    } on Object {
      if (uploadedPath != null) {
        await _tryRemoveUploadedAnnouncementImage(uploadedPath);
      }
      rethrow;
    }
    final saved = _announcementFromRow(
      Map<String, dynamic>.from(row)
        ..['announcement_event_links'] = [
          for (final eventId in linkedEventIds) {'event_id': eventId},
        ],
    );
    await _replaceAnnouncementEvents(
      announcementId: saved.id,
      eventIds: linkedEventIds,
    );
    return saved;
  }

  Future<AnnouncementItem> updateAnnouncement({
    required String id,
    required String title,
    required String body,
    required bool pinned,
    required bool isUrgent,
    List<String> linkedEventIds = const [],
    String? existingImageUrl,
    String? imageBase64,
    String? imageName,
    bool removeImage = false,
    List<String> pollOptions = const [],
    String pollQuestion = '',
  }) async {
    String? uploadedPath;
    var imageUrl = removeImage ? null : existingImageUrl;
    if (imageBase64 != null) {
      final uploaded = await _uploadAnnouncementImage(imageBase64, imageName);
      uploadedPath = uploaded.path;
      imageUrl = uploaded.url;
    }
    final payload = <String, dynamic>{
      'title': title,
      'body': body,
      'pinned': pinned,
      'is_urgent': isUrgent,
      'image_url': imageUrl,
      'poll_options': pollOptions,
      'poll_question': pollQuestion,
      'updated_by': _userId,
    };
    final Map<String, dynamic> row;
    try {
      row = await _writeAnnouncement(
        () => _client
            .from('announcements')
            .update(payload)
            .eq('id', id)
            .select(_announcementSelection)
            .single(),
        () => _client
            .from('announcements')
            .update(
              Map<String, dynamic>.from(payload)
                ..remove('is_urgent')
                ..remove('image_url')
                ..remove('poll_options')
                ..remove('poll_question'),
            )
            .eq('id', id)
            .select(_legacyAnnouncementSelection)
            .single(),
        requiresCurrentSchema:
            existingImageUrl != null ||
            imageBase64 != null ||
            removeImage ||
            pollOptions.isNotEmpty ||
            pollQuestion.trim().isNotEmpty,
      );
    } on Object {
      if (uploadedPath != null) {
        await _tryRemoveUploadedAnnouncementImage(uploadedPath);
      }
      rethrow;
    }
    final saved = _announcementFromRow(
      Map<String, dynamic>.from(row)
        ..['announcement_event_links'] = [
          for (final eventId in linkedEventIds) {'event_id': eventId},
        ],
    );
    await _replaceAnnouncementEvents(
      announcementId: saved.id,
      eventIds: linkedEventIds,
    );
    if ((removeImage || imageBase64 != null) && existingImageUrl != null) {
      await _tryRemoveAnnouncementImage(existingImageUrl);
    }
    return saved;
  }

  Future<List<Map<String, dynamic>>> _selectAnnouncementRows(
    Future<List<Map<String, dynamic>>> Function(String selection) query,
  ) async {
    try {
      return await query(_announcementSelection);
    } on PostgrestException catch (error) {
      if (!_isMissingAnnouncementFeature(error)) rethrow;
      return query(_legacyAnnouncementSelection);
    }
  }

  Future<Map<String, dynamic>> _writeAnnouncement(
    Future<Map<String, dynamic>> Function() current,
    Future<Map<String, dynamic>> Function() legacy, {
    bool requiresCurrentSchema = false,
  }) async {
    try {
      return await current();
    } on PostgrestException catch (error) {
      if (!_isMissingAnnouncementFeature(error)) rethrow;
      if (requiresCurrentSchema) {
        throw const LockerRepositoryException(
          '서버에 공지 사진·투표 마이그레이션을 먼저 적용해 주세요.',
        );
      }
      return legacy();
    }
  }

  AnnouncementItem _announcementFromRow(Map<String, dynamic> row) {
    final author = row['profiles'] as Map?;
    final votes = (row['announcement_poll_votes'] as List? ?? const [])
        .cast<Map>();
    final counts = <int, int>{};
    int? myPollOption;
    for (final vote in votes) {
      final option = vote['option_index'] as int?;
      if (option == null) continue;
      counts.update(option, (count) => count + 1, ifAbsent: () => 1);
      if (vote['profile_id'] == _client.auth.currentUser?.id) {
        myPollOption = option;
      }
    }
    return AnnouncementItem(
      id: row['id'] as String,
      title: row['title'] as String,
      body: row['body'] as String,
      author:
          author?['name'] as String? ??
          author?['display_name'] as String? ??
          '운영진',
      publishedAt: DateTime.parse(row['published_at'] as String).toLocal(),
      pinned: row['pinned'] as bool? ?? false,
      isUrgent: row['is_urgent'] as bool? ?? false,
      linkedEventIds: (row['announcement_event_links'] as List? ?? const [])
          .map((item) => (item as Map)['event_id'] as String)
          .toList(growable: false),
      imageUrl: row['image_url'] as String?,
      pollOptions: (row['poll_options'] as List?)?.cast<String>() ?? const [],
      pollQuestion: row['poll_question'] as String? ?? '',
      pollVotes: counts,
      myPollOption: myPollOption,
    );
  }

  Future<({String path, String url})> _uploadAnnouncementImage(
    String imageBase64,
    String? imageName,
  ) async {
    final lowerName = imageName?.toLowerCase() ?? '';
    final extension = lowerName.endsWith('.png')
        ? 'png'
        : lowerName.endsWith('.webp')
        ? 'webp'
        : 'jpg';
    final contentType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path = '$_userId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _client.storage
        .from('announcement-media')
        .uploadBinary(
          path,
          base64Decode(imageBase64),
          fileOptions: FileOptions(contentType: contentType),
        );
    return (
      path: path,
      url: _client.storage.from('announcement-media').getPublicUrl(path),
    );
  }

  Future<void> _removeAnnouncementImage(String imageUrl) async {
    const marker = '/object/public/announcement-media/';
    final index = imageUrl.indexOf(marker);
    if (index < 0) return;
    final path = Uri.decodeComponent(imageUrl.substring(index + marker.length));
    if (path.isNotEmpty) {
      await _client.storage.from('announcement-media').remove([path]);
    }
  }

  Future<void> _tryRemoveAnnouncementImage(String imageUrl) async {
    try {
      await _removeAnnouncementImage(imageUrl);
    } on Object catch (error, stackTrace) {
      debugPrint(
        'ENCBA announcement image cleanup failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> _tryRemoveUploadedAnnouncementImage(String path) async {
    try {
      await _client.storage.from('announcement-media').remove([path]);
    } on Object catch (error, stackTrace) {
      debugPrint(
        'ENCBA uploaded announcement cleanup failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> _replaceAnnouncementEvents({
    required String announcementId,
    required List<String> eventIds,
  }) => _client.rpc(
    'replace_announcement_events',
    params: {
      'requested_announcement_id': announcementId,
      'requested_event_ids': eventIds,
    },
  );

  Future<void> deleteAnnouncement(String id, {String? imageUrl}) async {
    await _client.from('announcements').delete().eq('id', id);
    if (imageUrl != null) await _tryRemoveAnnouncementImage(imageUrl);
  }

  Future<void> voteAnnouncement(String announcementId, int optionIndex) =>
      _client.from('announcement_poll_votes').upsert({
        'announcement_id': announcementId,
        'profile_id': _userId,
        'option_index': optionIndex,
        'voted_at': DateTime.now().toUtc().toIso8601String(),
      });

  /// 공지 투표 항목별로 "누가" 골랐는지 개별 응답자를 읽는다. 집계 카운트만
  /// 담는 `_announcementSelection`과 달리 투표 현황 화면 전용으로 필요할
  /// 때만 부른다. `announcement_poll_votes_read` 정책이 이미 전체 인증
  /// 사용자에게 열려 있어 별도 RPC 없이 다른 조인 select들과 같은 방식으로
  /// 읽는다.
  Future<List<AnnouncementPollVoter>> loadAnnouncementPollVoters(
    String announcementId,
  ) async {
    final rows = await _client
        .from('announcement_poll_votes')
        .select('profile_id,option_index,profiles(name,display_name)')
        .eq('announcement_id', announcementId);
    return (rows as List)
        .map((row) {
          final map = Map<String, dynamic>.from(row as Map);
          final profile = map['profiles'] as Map?;
          return AnnouncementPollVoter(
            profileId: map['profile_id'] as String,
            name:
                profile?['name'] as String? ??
                profile?['display_name'] as String? ??
                '알 수 없음',
            optionIndex: map['option_index'] as int,
          );
        })
        .toList(growable: false);
  }

  RealtimeChannel subscribeToAnnouncements(
    void Function(Map<String, dynamic> record) onInsert,
  ) => _client
      .channel('encba-announcements')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'announcements',
        callback: (payload) => onInsert(payload.newRecord),
      )
      .subscribe();

  Future<List<AuditEntry>> loadAuditLogs() async {
    final rows = await _client
        .from('audit_logs')
        .select(
          'entity_table,action,created_at,profiles!audit_logs_actor_id_fkey(name)',
        )
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map((row) {
      final actor = row['profiles'] as Map?;
      return AuditEntry(
        table: row['entity_table'] as String,
        action: row['action'] as String,
        actor: actor?['name'] as String? ?? '시스템',
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
    }).toList();
  }
}
