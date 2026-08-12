import 'dart:async';
import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class EncbaAuthException implements Exception {
  const EncbaAuthException(this.message);
  final String message;
}

class SupabaseAuthRepository {
  SupabaseAuthRepository(this._client, this._store);

  final supabase.SupabaseClient _client;
  final LocalStore _store;

  Stream<supabase.AuthState> get authChanges => _client.auth.onAuthStateChange;

  Future<UserProfile?> restoreSession() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return _profileFor(user.id);
  }

  Future<UserProfile> signUp({
    required UserProfile profile,
    required String password,
  }) async {
    if (password.length < 8) {
      throw const EncbaAuthException('비밀번호는 8자 이상으로 입력해 주세요.');
    }
    try {
      final response = await _client.auth.signUp(
        email: _internalEmail(profile.name),
        password: password,
        data: {
          'name': profile.name,
          'student_year': _studentYear(profile.studentId),
          'generation': profile.generation,
          'phone': profile.phone,
          'position': profile.position,
          'jersey_number': profile.jerseyNumber,
        },
      );
      final user = response.user;
      if (user == null) {
        throw const EncbaAuthException('계정을 만들지 못했습니다. 다시 시도해 주세요.');
      }
      if (response.session == null) {
        throw const EncbaAuthException('가입 확인 메일을 보냈습니다. 메일 인증 후 로그인해 주세요.');
      }
      return await _profileFor(user.id);
    } on supabase.AuthException catch (error) {
      throw EncbaAuthException(_friendlyAuthMessage(error.message));
    } on supabase.PostgrestException catch (error) {
      throw EncbaAuthException(_friendlyDatabaseMessage(error));
    }
  }

  Future<UserProfile> signIn(String loginName, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: _internalEmail(loginName),
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw const EncbaAuthException('실명 또는 비밀번호를 확인해 주세요.');
      }
      return await _profileFor(user.id);
    } on supabase.AuthException catch (error) {
      throw EncbaAuthException(_friendlyAuthMessage(error.message));
    } on supabase.PostgrestException catch (error) {
      throw EncbaAuthException(_friendlyDatabaseMessage(error));
    }
  }

  Future<UserProfile> refreshProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) throw const EncbaAuthException('로그인이 필요합니다.');
    return _profileFor(user.id);
  }

  Future<UserProfile> updateProfile(UserProfile profile) async {
    final user = _client.auth.currentUser;
    if (user == null || profile.id != user.id) {
      throw const EncbaAuthException('본인 프로필만 수정할 수 있습니다.');
    }
    try {
      String? avatarPath;
      String? previousAvatarPath;
      if (profile.photoBase64 != null && profile.photoBase64!.isNotEmpty) {
        final current = await _client
            .from('profiles')
            .select('avatar_path')
            .eq('id', user.id)
            .single();
        previousAvatarPath = current['avatar_path'] as String?;
        final bytes = base64Decode(profile.photoBase64!);
        avatarPath =
            '${user.id}/profile-${DateTime.now().microsecondsSinceEpoch}.jpg';
        await _client.storage
            .from('avatars')
            .uploadBinary(
              avatarPath,
              bytes,
              fileOptions: const supabase.FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
                cacheControl: '3600',
              ),
            );
      }
      final updates = <String, dynamic>{
        'display_name': profile.displayName ?? profile.name,
        'phone': profile.phone,
        'position': profile.position,
        'jersey_number': profile.jerseyNumber,
      };
      if (avatarPath != null) updates['avatar_path'] = avatarPath;
      try {
        await _client.from('profiles').update(updates).eq('id', user.id);
      } on Object {
        if (avatarPath != null) {
          try {
            await _client.storage.from('avatars').remove([avatarPath]);
          } on Object {
            // 실패한 신규 업로드 정리는 본래 DB 오류를 가리지 않는다.
          }
        }
        rethrow;
      }
      if (previousAvatarPath != null && previousAvatarPath != avatarPath) {
        try {
          await _client.storage.from('avatars').remove([previousAvatarPath]);
        } on Object {
          // 새 프로필 적용 성공 여부와 이전 이미지 정리는 분리한다.
        }
      }
      return await _profileFor(user.id);
    } on supabase.AuthException catch (error) {
      throw EncbaAuthException(_friendlyAuthMessage(error.message));
    } on supabase.PostgrestException catch (error) {
      throw EncbaAuthException(_friendlyDatabaseMessage(error));
    } on supabase.StorageException catch (error) {
      throw EncbaAuthException('프로필 사진을 저장하지 못했습니다: ${error.message}');
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<UserProfile> _profileFor(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select(
            'id,email,name,display_name,student_year,generation,phone,position,'
            'jersey_number,membership_status,badge,avatar_path,is_admin,is_schedule_manager,is_active,'
            'profile_teams(teams(code))',
          )
          .eq('id', userId)
          .single();
      final normalized = Map<String, dynamic>.from(row);
      normalized['teams'] = (row['profile_teams'] as List? ?? const [])
          .map((item) => (item as Map)['teams'])
          .whereType<Map>()
          .map((team) => team['code'] as String)
          .toList();
      final avatarPath = row['avatar_path'] as String?;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        try {
          final bytes = await _client.storage
              .from('avatars')
              .download(avatarPath);
          normalized['photo_base64'] = base64Encode(bytes);
        } on Object {
          // 프로필 본문은 사진 다운로드 실패와 무관하게 사용할 수 있어야 한다.
        }
      }
      final profile = UserProfile.fromSupabase(normalized);
      if (!profile.isActive) {
        await _client.auth.signOut();
        throw const EncbaAuthException('비활성화된 계정입니다. 관리자에게 문의해 주세요.');
      }
      try {
        await _store.setString(
          _profileCacheKey(userId),
          jsonEncode(profile.toJson()),
        );
      } on Object {
        // 서버에서 받은 최신 프로필은 로컬 캐시 저장 실패와 무관하게 사용한다.
      }
      return profile;
    } on EncbaAuthException {
      rethrow;
    } on Object {
      final cached = await _store.getString(_profileCacheKey(userId));
      if (cached == null) rethrow;
      return UserProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(cached) as Map),
      );
    }
  }

  String _profileCacheKey(String userId) => 'encba.profile.$userId.v1';

  String _internalEmail(String loginName) {
    final canonical = loginName.trim();
    final encoded = base64Url
        .encode(utf8.encode(canonical))
        .replaceAll('=', '');
    return 'encba.$encoded@members.encba.local';
  }

  int _studentYear(String value) =>
      int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  String _friendlyAuthMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return '실명 또는 비밀번호를 확인해 주세요.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Supabase에서 이메일 확인을 끈 뒤 다시 가입해 주세요.';
    }
    if (lower.contains('already registered') ||
        lower.contains('already been registered')) {
      return '이미 가입된 실명 계정입니다.';
    }
    if (lower.contains('rate limit')) {
      return '요청이 너무 많습니다. 잠시 뒤 다시 시도해 주세요.';
    }
    return '계정 서버 요청에 실패했습니다. 잠시 뒤 다시 시도해 주세요.';
  }

  String _friendlyDatabaseMessage(supabase.PostgrestException error) {
    if (error.code == '42501') return '이 작업을 수행할 권한이 없습니다.';
    if (error.code == '23505') return '이미 등록된 정보입니다.';
    return '계정 정보를 불러오지 못했습니다. 잠시 뒤 다시 시도해 주세요.';
  }
}
