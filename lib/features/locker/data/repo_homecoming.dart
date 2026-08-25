part of 'supabase_locker_repository.dart';

/// HomecomingApi - 리포지토리를 테이블·도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin HomecomingApi on RepoCore {
  @override
  SupabaseClient get _client;

  @override
  String get _userId;

  Future<List<HomecomingContact>> loadHomecomingContacts() async {
    final rows = await _client
        .from('homecoming_contacts')
        .select(
          'id,source_row,senior_name,generation,home_or_office_phone,phone,'
          'contact_status,parking_required,parking_registered,follow_up_allowed,'
          'follow_up_on,notes,assigned_to,assigned_to_name,'
          'homecoming_campaigns!inner(is_active)',
        )
        .eq('homecoming_campaigns.is_active', true)
        .order('generation', ascending: false, nullsFirst: false)
        .limit(1000);
    return rows
        .map(
          (row) => HomecomingContact(
            id: row['id'] as String,
            name: row['senior_name'] as String,
            phone: row['phone'] as String,
            status: row['contact_status'] as String,
            generation: row['generation'] as int?,
            parkingRequired: row['parking_required'] as bool?,
            parkingRegistered: row['parking_registered'] as bool? ?? false,
            homeOrOfficePhone: row['home_or_office_phone'] as String?,
            followUpAllowed: row['follow_up_allowed'] as bool?,
            followUpOn: row['follow_up_on'] == null
                ? null
                : DateTime.parse(row['follow_up_on'] as String),
            notes: row['notes'] as String?,
            sourceRow: row['source_row'] as int?,
            assignedToId: row['assigned_to'] as String?,
            assignedToName: row['assigned_to_name'] as String?,
          ),
        )
        .toList();
  }

  Future<void> updateHomecomingContact(HomecomingContact contact) => _client
      .from('homecoming_contacts')
      .update({
        'contact_status': contact.status,
        'parking_required': contact.parkingRequired,
        'parking_registered': contact.parkingRegistered,
        'follow_up_allowed': contact.followUpAllowed,
        'follow_up_on': contact.followUpOn?.toIso8601String().split('T').first,
        'notes': contact.notes,
        'last_contacted_at': contact.handled
            ? DateTime.now().toUtc().toIso8601String()
            : null,
      })
      .eq('id', contact.id);

  Future<void> assignHomecomingContact({
    required String id,
    String? assignedToId,
    String? assignedToName,
  }) => _client
      .from('homecoming_contacts')
      .update({'assigned_to': assignedToId, 'assigned_to_name': assignedToName})
      .eq('id', id);

  Future<HomecomingCampaign?> loadActiveHomecomingCampaign() async {
    final rows = await _client
        .from('homecoming_campaigns')
        .select()
        .eq('is_active', true)
        .limit(1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return HomecomingCampaign(
      id: row['id'] as String,
      title: row['title'] as String,
      academicYear: row['academic_year'] as int,
      term: row['term'] as int,
      eventDate: DateTime.parse(row['event_date'] as String),
      startsAt: row['starts_at'] as String,
      endsAt: row['ends_at'] as String,
      venue: row['venue'] as String,
      isActive: row['is_active'] as bool,
      afterpartyNote: row['afterparty_note'] as String,
      sourceFileName: row['source_file_name'] as String?,
    );
  }

  Future<HomecomingCampaign> activateHomecomingCampaign({
    required int academicYear,
    required int term,
    required DateTime eventDate,
    required String startsAt,
    required String endsAt,
    required String venue,
  }) async {
    await _client
        .from('homecoming_campaigns')
        .update({'is_active': false})
        .eq('is_active', true);
    await _client
        .from('homecoming_campaigns')
        .upsert({
          'academic_year': academicYear,
          'term': term,
          'title': '$academicYear-$term 홈커밍',
          'event_date': eventDate.toIso8601String().split('T').first,
          'starts_at': startsAt,
          'ends_at': endsAt,
          'venue': venue,
          'is_active': true,
          'created_by': _userId,
        }, onConflict: 'academic_year,term')
        .select()
        .single();
    return (await loadActiveHomecomingCampaign())!;
  }

  Future<void> deactivateHomecomingCampaign(String campaignId) => _client
      .from('homecoming_campaigns')
      .update({'is_active': false})
      .eq('id', campaignId);

  Future<void> importHomecomingContacts({
    required String campaignId,
    required String fileName,
    required List<Map<String, dynamic>> contacts,
  }) => _client.rpc(
    'import_homecoming_contacts',
    params: {
      'requested_campaign_id': campaignId,
      'requested_file_name': fileName,
      'requested_contacts': contacts,
    },
  );

  /// 관리자가 연락 보드에서 선배를 한 명 직접 추가한다. 엑셀 가져오기 없이
  /// 빠진 선배를 보충할 때 쓴다. RLS가 관리자에게만 insert를 허용한다.
  Future<void> addHomecomingContact({
    required String campaignId,
    required String name,
    required String phone,
    int? generation,
    String? assignedToId,
    String? assignedToName,
  }) => _client.from('homecoming_contacts').insert({
    'campaign_id': campaignId,
    'senior_name': name,
    'phone': phone,
    'generation': generation,
    'assigned_to': assignedToId,
    'assigned_to_name': assignedToName,
  });

  Future<void> deleteHomecomingContact(String id) =>
      _client.from('homecoming_contacts').delete().eq('id', id);
}
