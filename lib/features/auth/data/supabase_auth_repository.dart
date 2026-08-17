import 'dart:async';
import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class EncbaAuthException implements Exception {
  const EncbaAuthException(this.message);
  final String message;
}

class AuthSessionSnapshot {
  const AuthSessionSnapshot({this.profile, this.pendingRegistration});

  final UserProfile? profile;
  final PendingGoogleRegistration? pendingRegistration;
}

class SupabaseAuthRepository {
  SupabaseAuthRepository(this._client, this._store);

  final supabase.SupabaseClient _client;
  final LocalStore _store;

  Stream<supabase.AuthState> get authChanges => _client.auth.onAuthStateChange;

  /// Google에서 돌아온 주소에 실패 흔적이 있으면 그 사유를 돌려준다.
  /// 이게 없으면 인증이 실패해도 그냥 로그인 화면으로 돌아온 것처럼 보인다.
  String? pendingOAuthError() {
    if (!kIsWeb) return null;
    final uri = Uri.base;
    // implicit 흐름은 값을 프래그먼트에 싣는다. 앱 경로(`#/...`)와는 구분한다.
    final fragment = uri.fragment.startsWith('/')
        ? const <String, String>{}
        : Uri.splitQueryString(uri.fragment);
    final failure = uri.queryParameters['error'] ?? fragment['error'];
    if (failure != null) {
      final reason =
          uri.queryParameters['error_code'] ?? fragment['error_code'];
      // 인증을 시작한 주소와 돌아온 주소가 다르면 교환용 정보가 남아 있지
      // 않아 이 코드가 뜬다. Supabase의 Redirect URLs 설정을 봐야 한다.
      if (reason == 'flow_state_already_used' ||
          reason == 'flow_state_not_found') {
        return '로그인을 시작한 주소(${uri.origin})와 돌아온 주소가 달라 인증이 끊겼습니다. '
            'Supabase의 Redirect URLs에 이 주소를 추가해 주세요.';
      }
      final detail =
          uri.queryParameters['error_description'] ??
          fragment['error_description'];
      return detail == null || detail.isEmpty
          ? 'Google 인증이 취소되었거나 거부되었습니다. ($failure)'
          : 'Google 인증에 실패했습니다: $detail';
    }
    // 인증 코드는 받았는데 세션이 안 생겼다면 코드 교환에서 끊긴 것이다.
    final hasCode =
        uri.queryParameters.containsKey('code') || fragment.containsKey('code');
    if (hasCode && _client.auth.currentSession == null) {
      return 'Google 인증 코드를 세션으로 바꾸지 못했습니다. '
          'Supabase의 Redirect URLs에 ${uri.origin} 주소가 있는지 확인해 주세요.';
    }
    return null;
  }

  Future<AuthSessionSnapshot> restoreSession() async {
    var user = _client.auth.currentUser;
    if (user == null) return const AuthSessionSnapshot();
    // 아직 넉넉히 남은 세션까지 새로 고치지 않는다. Google 로그인 직후처럼
    // 방금 발급된 토큰을 다시 돌리면 refresh token 회전이 겹쳐 거절당하고,
    // 그 예외를 로그아웃으로 처리해 곧장 로그인 화면으로 튕기게 된다.
    if (_needsRefresh(_client.auth.currentSession)) {
      try {
        final refreshed = await _client.auth.refreshSession();
        user = refreshed.user ?? _client.auth.currentUser;
      } on supabase.AuthRetryableFetchException {
        // 오프라인에서는 저장된 세션과 캐시로 앱을 계속 사용할 수 있다.
      } on supabase.AuthException {
        // 갱신이 거절돼도 아직 만료 전이라면 지금 세션으로 계속 쓴다.
        if (_client.auth.currentSession?.isExpired ?? true) {
          await _client.auth.signOut(scope: supabase.SignOutScope.local);
          return const AuthSessionSnapshot();
        }
        user = _client.auth.currentUser;
      }
    }
    if (user == null) return const AuthSessionSnapshot();
    return _sessionFor(user);
  }

  /// 만료됐거나 곧 만료될 세션만 미리 갱신한다.
  static bool _needsRefresh(supabase.Session? session) {
    if (session == null) return false;
    if (session.isExpired) return true;
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return false;
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    return expiry.difference(DateTime.now()) < const Duration(minutes: 5);
  }

  /// 가입과 로그인이 같은 흐름을 탄다. 인증이 끝나면 [_sessionFor]가 프로필
  /// 유무를 보고 곧바로 로그인시키거나 회원정보 입력을 요청한다.
  ///
  /// [forSignUp]이면 이미 가입된 계정인지 따져 되돌려보낸다. 리디렉트로 앱이
  /// 새로 뜨는 사이에 이 의도가 사라지므로 로컬에 적어 두고 콜백에서 읽는다.
  Future<void> startGoogleSignIn({bool forSignUp = false}) async {
    try {
      if (forSignUp) {
        await _store.setString(_googleSignUpIntentKey, 'true');
      } else {
        await _store.remove(_googleSignUpIntentKey);
      }
    } on Object {
      // 의도를 적어 두지 못해도 인증 자체는 진행한다.
    }
    try {
      final opened = await _client.auth.signInWithOAuth(
        supabase.OAuthProvider.google,
        redirectTo: kIsWeb ? '${Uri.base.origin}/sign-in' : null,
        queryParams: const {'hd': 'snu.ac.kr', 'prompt': 'select_account'},
      );
      if (!opened) {
        throw const EncbaAuthException('Google 로그인 화면을 열지 못했습니다.');
      }
    } on supabase.AuthException catch (error) {
      throw EncbaAuthException(_friendlyAuthMessage(error.message));
    }
  }

  Future<UserProfile> completeGoogleRegistration(
    UserProfile profile, {
    required String password,
  }) async {
    final registration = _pendingRegistrationFor(_client.auth.currentUser);
    if (registration == null) {
      throw const EncbaAuthException('Google 인증을 먼저 완료해 주세요.');
    }
    if (!isSnuSchoolEmail(registration.email)) {
      await _client.auth.signOut();
      throw const EncbaAuthException('서울대학교 학교 계정으로 가입해 주세요.');
    }
    if (password.length < 8) {
      throw const EncbaAuthException('비밀번호는 8자 이상으로 입력해 주세요.');
    }
    // 비밀번호를 먼저 건다. 프로필을 만든 뒤에 실패하면 계정은 있는데
    // 비밀번호만 없는 상태로 남아, 무엇을 다시 해야 하는지 알기 어렵다.
    // 이 순서면 어느 단계에서 끊겨도 처음부터 다시 눌러 이어갈 수 있다.
    try {
      await _client.auth.updateUser(
        supabase.UserAttributes(password: password),
      );
    } on supabase.AuthException catch (error) {
      throw EncbaAuthException(_friendlyAuthMessage(error.message));
    }
    try {
      await _client.rpc(
        'complete_google_registration',
        params: {
          'requested_name': profile.name,
          'requested_student_year': _studentYear(profile.studentId),
          'requested_joined_year': profile.joinedYear,
          'requested_phone': profile.phone,
          'requested_position': profile.position,
          'requested_jersey_number': profile.jerseyNumber,
        },
      );
      return await _profileFor(_client.auth.currentUser!.id);
    } on supabase.AuthException catch (error) {
      throw EncbaAuthException(_friendlyAuthMessage(error.message));
    } on supabase.PostgrestException catch (error) {
      throw EncbaAuthException(_friendlyDatabaseMessage(error));
    }
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
          'joined_year': profile.joinedYear,
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

  /// 실명 또는 학교 이메일 어느 쪽으로도 들어올 수 있다. Google로 가입한
  /// 부원의 계정 이메일은 학교 이메일이라 실명으로 만든 내부 주소와 다르다.
  Future<UserProfile> signIn(String loginName, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: loginIdToEmail(loginName),
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw const EncbaAuthException('아이디 또는 비밀번호를 확인해 주세요.');
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

  Future<AuthSessionSnapshot> refreshSessionState() async {
    final user = _client.auth.currentUser;
    if (user == null) return const AuthSessionSnapshot();
    return _sessionFor(user);
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
        'student_year': _studentYear(profile.studentId),
        'joined_year': profile.joinedYear,
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

  Future<AuthSessionSnapshot> _sessionFor(supabase.User user) async {
    final wantedSignUp = await _consumeGoogleSignUpIntent();
    final profile = await _profileForIfExists(user.id);
    if (profile != null) {
      // 가입하러 들어왔는데 이미 계정이 있으면 그대로 들여보내지 않고 알린다.
      // 조용히 로그인시키면 새 계정이 만들어진 줄 알기 쉽다.
      if (wantedSignUp && _hasGoogleIdentity(user)) {
        await _client.auth.signOut();
        throw EncbaAuthException(
          '이미 가입된 Google 계정입니다. ${user.email ?? '학교 계정'}으로 로그인해 주세요.',
        );
      }
      return AuthSessionSnapshot(profile: profile);
    }
    final pendingRegistration = _pendingRegistrationFor(user);
    if (pendingRegistration == null) {
      throw const EncbaAuthException('가입 정보를 찾지 못했습니다. 관리자에게 문의해 주세요.');
    }
    if (!isSnuSchoolEmail(pendingRegistration.email)) {
      await _client.auth.signOut();
      throw const EncbaAuthException('서울대학교 학교 계정으로 가입해 주세요.');
    }
    return AuthSessionSnapshot(pendingRegistration: pendingRegistration);
  }

  static const _googleSignUpIntentKey = 'encba.google-signup-intent.v1';

  /// 가입 의도는 한 번만 쓴다. 남겨 두면 다음에 앱을 열 때 엉뚱하게 걸린다.
  Future<bool> _consumeGoogleSignUpIntent() async {
    try {
      final value = await _store.getString(_googleSignUpIntentKey);
      if (value == null) return false;
      await _store.remove(_googleSignUpIntentKey);
      return value == 'true';
    } on Object {
      return false;
    }
  }

  bool _hasGoogleIdentity(supabase.User user) {
    final providers = user.appMetadata['providers'];
    return user.appMetadata['provider'] == 'google' ||
        (providers is List && providers.contains('google'));
  }

  PendingGoogleRegistration? _pendingRegistrationFor(supabase.User? user) {
    if (user == null || user.email == null) return null;
    if (!_hasGoogleIdentity(user)) return null;
    final metadata = user.userMetadata;
    final suggestedName =
        metadata?['full_name'] as String? ?? metadata?['name'] as String? ?? '';
    return PendingGoogleRegistration(
      email: user.email!,
      suggestedName: suggestedName,
    );
  }

  Future<UserProfile?> _profileForIfExists(String userId) async {
    try {
      return await _profileFor(userId);
    } on supabase.PostgrestException catch (error) {
      if (error.code == 'PGRST116') return null;
      rethrow;
    }
  }

  Future<UserProfile> _profileFor(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select(
            'id,email,name,display_name,student_year,generation,joined_year,phone,position,'
            'jersey_number,membership_status,badge,avatar_path,is_admin,is_schedule_manager,is_active,leadership_role,is_reservation_manager,'
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

  /// 로그인 아이디를 Supabase 계정 이메일로 옮긴다. `@`가 들어 있으면 이미
  /// 이메일이므로 그대로 쓰고, 아니면 실명으로 만든 내부 주소를 쓴다.
  String loginIdToEmail(String loginId) {
    final value = loginId.trim();
    return value.contains('@') ? value.toLowerCase() : _internalEmail(value);
  }

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
      return '아이디 또는 비밀번호를 확인해 주세요.';
    }
    if (lower.contains('password') && lower.contains('should be at least')) {
      return '비밀번호는 8자 이상으로 입력해 주세요.';
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
    if (error.message.contains('ENCBA_SNU_GOOGLE_ACCOUNT_REQUIRED')) {
      return '서울대학교 학교 계정으로 가입해 주세요.';
    }
    if (error.message.contains('ENCBA_GOOGLE_AUTH_REQUIRED')) {
      return 'Google 인증을 먼저 완료해 주세요.';
    }
    if (error.message.contains('ENCBA_MEMBER_NOT_ALLOWLISTED')) {
      return '가입 명단에서 실명을 찾지 못했습니다. 관리자에게 문의해 주세요.';
    }
    if (error.message.contains('ENCBA_GOOGLE_REGISTRATION_INVALID')) {
      return '입력한 회원정보를 다시 확인해 주세요.';
    }
    if (error.code == '42501') return '이 작업을 수행할 권한이 없습니다.';
    if (error.code == '23505') return '이미 등록된 정보입니다.';
    return '계정 정보를 불러오지 못했습니다. 잠시 뒤 다시 시도해 주세요.';
  }
}
