import 'dart:convert';
import 'dart:math';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class EncbaAuthException implements Exception {
  const EncbaAuthException(this.message);
  final String message;
}

/// 비활성화된 계정으로 로그인했을 때. 로그인 화면이 그 자리에서 관리자에게
/// 활성화를 요청할 수 있도록, 어떤 계정이었는지를 함께 들고 나온다.
class EncbaInactiveAccountException extends EncbaAuthException {
  const EncbaInactiveAccountException(this.email)
    : super('비활성화된 계정입니다. 관리자에게 활성화를 요청해 주세요.');

  final String email;
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

  /// 세션 복원을 기다리지 않고 지금 메모리에 있는 사용자 ID.
  /// 캐시 프로필로 첫 화면을 빠르게 그릴 때만 쓴다.
  String? get currentUserId => _client.auth.currentUser?.id;

  /// 저장해 둔 프로필 캐시를 읽는다. 세션 복원 직후 네트워크 왕복 없이
  /// 화면을 먼저 그리는 데 쓰고, 이후 서버 값으로 조용히 덮어쓴다.
  Future<UserProfile?> loadCachedProfile(String userId) async {
    try {
      final cached = await _store.getString(_profileCacheKey(userId));
      if (cached == null) return null;
      return UserProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(cached) as Map),
      );
    } on Object {
      return null;
    }
  }

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

  /// Google 인증을 마친 사람의 회원 정보를 확정한다.
  ///
  /// [password]를 주지 않으면 아무도 모르는 무작위 비밀번호를 만들어 둔다.
  /// 로그인은 Google로만 하기 때문에 가입할 때 비밀번호를 받지 않는다.
  /// 계정에 비밀번호 자리는 있어야 해서 채워만 두는 값이다.
  Future<UserProfile> completeGoogleRegistration(
    UserProfile profile, {
    String? password,
  }) async {
    final registration = _pendingRegistrationFor(_client.auth.currentUser);
    if (registration == null) {
      throw const EncbaAuthException('Google 인증을 먼저 완료해 주세요.');
    }
    if (!isSnuSchoolEmail(registration.email)) {
      await _client.auth.signOut();
      throw const EncbaAuthException('서울대학교 학교 계정으로 가입해 주세요.');
    }
    final resolvedPassword = password == null || password.isEmpty
        ? _generatedPassword()
        : password;
    if (resolvedPassword.length < 8) {
      throw const EncbaAuthException('비밀번호는 8자 이상으로 입력해 주세요.');
    }
    final userId = _client.auth.currentUser!.id;
    try {
      await _client.functions.invoke(
        'complete-google-registration',
        body: {
          'requested_name': profile.name,
          'requested_student_year': _studentYear(profile.studentId),
          'requested_joined_year': profile.joinedYear,
          'requested_phone': profile.phone,
          'requested_position': profile.position,
          'requested_jersey_number': profile.jerseyNumber,
          'password': resolvedPassword,
        },
      );
      await _clearGoogleSignUpIntent();
      try {
        await _client.auth.refreshSession();
      } on supabase.AuthException {
        // 프로필 조회는 기존 토큰으로도 가능하다. 새 로그인 아이디는 다음 로그인부터 쓴다.
      }
      return await _profileFor(userId);
    } on supabase.AuthException catch (error) {
      throw EncbaAuthException(_friendlyAuthMessage(error.message));
    } on supabase.FunctionException catch (error) {
      if (error.status == 409) {
        await _clearGoogleSignUpIntent();
        await _client.auth.signOut();
      }
      throw EncbaAuthException(_friendlyFunctionMessage(error));
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
        email: internalLoginEmailForName(profile.name),
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

  /// 실명 또는 학교 이메일 어느 쪽으로도 들어올 수 있다. Google 가입 뒤 Auth의
  /// 기본 이메일은 실명용 내부 주소로 바뀌므로 학교 이메일은 서버에서 그 주소를
  /// 찾아 같은 비밀번호 로그인으로 이어 준다.
  Future<UserProfile> signIn(String loginName, String password) async {
    try {
      final value = loginName.trim();
      final attempted = <String>{};
      supabase.AuthException? lastInvalidCredentials;

      Future<UserProfile?> tryCandidates(Iterable<String> candidates) async {
        for (final candidate in candidates.where(attempted.add)) {
          try {
            final response = await _client.auth.signInWithPassword(
              email: candidate,
              password: password,
            );
            final user = response.user;
            if (user == null) {
              throw const EncbaAuthException('아이디 또는 비밀번호를 확인해 주세요.');
            }
            return await _profileFor(user.id);
          } on supabase.AuthException catch (error) {
            if (!_isInvalidLoginCredentials(error)) rethrow;
            lastInvalidCredentials = error;
          }
        }
        return null;
      }

      // 실명 로그인은 Auth 이메일을 로컬에서 결정할 수 있다. 일반 경로에서
      // Edge Function과 RPC 왕복을 먼저 기다리지 않고 곧바로 인증한다.
      final direct = await tryCandidates(directLoginEmails(value));
      if (direct != null) return direct;

      // 학교 이메일/이전 데이터처럼 서버 매핑이 필요한 경우에만 조회한다.
      final resolved = await tryCandidates(await _resolvedLoginEmails(value));
      if (resolved != null) return resolved;
      if (lastInvalidCredentials != null) throw lastInvalidCredentials!;
      throw const EncbaAuthException('아이디 또는 비밀번호를 확인해 주세요.');
    } on supabase.AuthException catch (error) {
      throw EncbaAuthException(_friendlyAuthMessage(error.message));
    } on supabase.PostgrestException catch (error) {
      throw EncbaAuthException(_friendlyDatabaseMessage(error));
    }
  }

  Future<List<String>> _resolvedLoginEmails(String value) async {
    final normalized = value.toLowerCase();
    final candidates = <String>[];
    void add(String? candidate) {
      final trimmed = candidate?.trim().toLowerCase();
      if (trimmed != null &&
          trimmed.isNotEmpty &&
          !candidates.contains(trimmed)) {
        candidates.add(trimmed);
      }
    }

    // 학교 이메일 전체 주소는 기존 Edge Function과 DB RPC 양쪽에서 찾고,
    // @ 앞 아이디만 입력한 경우에는 DB RPC가 보존된 학교 이메일로 계정을 찾는다.
    // 두 조회는 서로 독립적이라 순서대로 기다리지 않고 동시에 보낸다.
    Future<Object?> resolveViaFunction() async {
      try {
        final response = await _client.functions.invoke(
          'resolve-login-email',
          body: {'identifier': normalized, 'email': normalized},
        );
        return response.data;
      } on Object {
        // DB RPC 폴백이 있으므로 배포 시점이 다른 Edge Function 장애를 숨기지 않는다.
        return null;
      }
    }

    Future<Object?> resolveViaRpc() async {
      try {
        return await _client.rpc(
          'resolve_login_email',
          params: {'requested_identifier': normalized},
        );
      } on Object {
        // 이전 DB에서도 실명 로그인과 일반 이메일 직접 로그인은 계속 동작한다.
        return null;
      }
    }

    final results = await Future.wait([resolveViaFunction(), resolveViaRpc()]);
    if (results[0] is Map) {
      final resolved = (results[0]! as Map)['login_email'];
      if (resolved is String) add(resolved);
    }
    if (results[1] is String) add(results[1] as String);
    return candidates;
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
            '${user.id}/profile-${DateTime.now().microsecondsSinceEpoch}.png';
        await _client.storage
            .from('avatars')
            .uploadBinary(
              avatarPath,
              bytes,
              fileOptions: const supabase.FileOptions(
                contentType: 'image/png',
                upsert: true,
                cacheControl: '3600',
              ),
            );
      }
      final updates = <String, dynamic>{
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

  Future<void> signOut() async {
    await _clearGoogleSignUpIntent();
    await _client.auth.signOut();
  }

  Future<AuthSessionSnapshot> _sessionFor(supabase.User user) async {
    final wantedSignUp = await _hasGoogleSignUpIntent();
    final profile = await _profileForIfExists(user.id);
    if (profile != null) {
      // member_allowlist의 존재 여부가 아니라 Google 사용자에게 연결된 프로필이
      // 실제 가입 완료 여부를 결정한다. 가입 버튼으로 기존 계정에 들어온 경우에는
      // 조용히 로그인시키지 않고 분명한 안내를 보여 준다.
      if (wantedSignUp && _hasGoogleIdentity(user)) {
        await _clearGoogleSignUpIntent();
        await _client.auth.signOut();
        throw EncbaAuthException(
          '이미 등록된 계정입니다. 로그인 화면에서 Google 계정으로 로그인해 주세요.',
        );
      }
      return AuthSessionSnapshot(profile: profile);
    }
    final pendingRegistration = _pendingRegistrationFor(user);
    if (pendingRegistration == null) {
      throw const EncbaAuthException('가입 정보를 찾지 못했습니다. 관리자에게 문의해 주세요.');
    }
    if (!isSnuSchoolEmail(pendingRegistration.email)) {
      await _clearGoogleSignUpIntent();
      await _client.auth.signOut();
      throw const EncbaAuthException('서울대학교 학교 계정으로 가입해 주세요.');
    }
    return AuthSessionSnapshot(pendingRegistration: pendingRegistration);
  }

  static const _googleSignUpIntentKey = 'encba.google-signup-intent.v1';

  /// OAuth 리디렉트 직후 세션 복원과 인증 이벤트가 동시에 들어올 수 있으므로
  /// 가입 의도를 읽는 순간 지우지 않는다. 가입 완료·취소·중복 판정 시에만 지운다.
  Future<bool> _hasGoogleSignUpIntent() async {
    try {
      final value = await _store.getString(_googleSignUpIntentKey);
      return value == 'true';
    } on Object {
      return false;
    }
  }

  Future<void> _clearGoogleSignUpIntent() async {
    try {
      await _store.remove(_googleSignUpIntentKey);
    } on Object {
      // 로그인 상태 판정은 로컬 의도 정리 실패 때문에 막지 않는다.
    }
  }

  bool _hasGoogleIdentity(supabase.User user) {
    final providers = user.appMetadata['providers'];
    // identities가 가장 정확하다. app_metadata의 provider는 계정에 여러
    // 로그인 수단이 붙으면 마지막 것만 남거나 'email'로 굳어 버려서, 실제로
    // Google로 들어온 사람을 아니라고 판정하는 일이 있었다.
    final identities = user.identities;
    if (identities != null &&
        identities.any((identity) => identity.provider == 'google')) {
      return true;
    }
    return user.appMetadata['provider'] == 'google' ||
        (providers is List && providers.contains('google'));
  }

  /// 이 사람이 Google로 인증한 학교 메일.
  ///
  /// user.email은 실명 로그인용 가상 주소일 수 있다. 그 주소는 학교
  /// 도메인이 아니라서, 명단에 있는 부원인데도 "학교 계정으로 가입해
  /// 주세요"라는 엉뚱한 안내가 떴다. Google identity에 붙어 있는 메일을
  /// 먼저 보고, 없을 때만 계정 메일로 물러선다.
  String? _googleEmailFor(supabase.User user) {
    for (final identity in user.identities ?? const []) {
      if (identity.provider != 'google') continue;
      final email = identity.identityData?['email'];
      if (email is String && email.contains('@')) return email;
    }
    final email = user.email;
    return email != null && email.contains('@') ? email : null;
  }

  PendingGoogleRegistration? _pendingRegistrationFor(supabase.User? user) {
    if (user == null) return null;
    if (!_hasGoogleIdentity(user)) return null;
    final email = _googleEmailFor(user);
    if (email == null) return null;
    return PendingGoogleRegistration(
      email: email,
      suggestedName: googleRealNameFromMetadata(user.userMetadata),
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
        // avatars 버킷은 public이다. 로그인 경로에서 이미지 bytes를 직렬로
        // 내려받지 않고 URL만 넘겨 Flutter 이미지 캐시가 화면과 병렬로 받는다.
        normalized['avatar_url'] = _client.storage
            .from('avatars')
            .getPublicUrl(avatarPath);
      }
      final profile = UserProfile.fromSupabase(normalized);
      if (!profile.isActive) {
        // 세션은 바로 끊는다. 비활성 계정이 잠깐이라도 데이터를 읽을 수
        // 있으면 안 되기 때문이다. 대신 어떤 계정이었는지는 예외에 실어
        // 보내서, 로그인 화면이 세션 없이 활성화 요청을 넣을 수 있게 한다.
        final email = profile.email;
        await _client.auth.signOut();
        throw EncbaInactiveAccountException(email);
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

  /// 비활성 계정의 활성화를 관리자에게 요청한다. 이 시점에는 이미 로그아웃
  /// 상태라 anon 키로 부른다. 서버 함수는 계정이 있는지 없는지 알려 주지
  /// 않으므로, 실패는 연결 문제일 때만이다.
  Future<bool> requestAccountActivation(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _client.rpc(
        'request_account_activation',
        params: {'requested_email': trimmed},
      );
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA activation request failed: $error\n$stackTrace');
      return false;
    }
  }

  /// 아무도 모르는 비밀번호. 가입 화면에서 비밀번호를 받지 않으므로
  /// 계정의 빈자리를 채우는 용도로만 쓴다. 추측할 수 없어야 해서
  /// 암호학적 난수로 만든다.
  String _generatedPassword() {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      32,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String _profileCacheKey(String userId) => 'encba.profile.$userId.v1';

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

  bool _isInvalidLoginCredentials(supabase.AuthException error) =>
      error.code == 'invalid_credentials' ||
      error.message.toLowerCase().contains('invalid login credentials');

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

  String _friendlyFunctionMessage(supabase.FunctionException error) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    if (error.status == 401) return 'Google 인증을 다시 진행해 주세요.';
    return '계정 서버 요청에 실패했습니다. 잠시 뒤 다시 시도해 주세요.';
  }
}

/// 서울대 Google Workspace 표시명은 `최재원 / 학생 / 전기·정보공학부`처럼
/// 소속 정보까지 붙는다. 첫 구간만 실명으로 쓰고 보이지 않는 soft hyphen도 제거한다.
@visibleForTesting
String googleRealNameFromMetadata(Map<String, dynamic>? metadata) {
  final raw =
      metadata?['full_name'] as String? ?? metadata?['name'] as String? ?? '';
  return raw.replaceAll('\u00ad', '').split(RegExp(r'\s*/\s*')).first.trim();
}

/// 이메일 로컬 파트의 64자 제한과 대소문자 비구분을 모두 만족하도록 실명을
/// 고정 길이 소문자 SHA-256 식별자로 바꾼다.
@visibleForTesting
String internalLoginEmailForName(String loginName) {
  final digest = sha256.convert(utf8.encode(loginName.trim())).toString();
  return '$digest@members.encba.local';
}

/// 기존 실명 계정의 Base64URL 주소를 로그인 호환용으로만 유지한다.
@visibleForTesting
String legacyInternalLoginEmailForName(String loginName) {
  final encoded = base64Url
      .encode(utf8.encode(loginName.trim()))
      .replaceAll('=', '');
  return 'encba.$encoded@members.encba.local';
}

/// 네트워크 조회 없이 즉시 시도할 수 있는 로그인 이메일 후보.
@visibleForTesting
List<String> directLoginEmails(String loginName) {
  final value = loginName.trim();
  if (value.contains('@')) return [value.toLowerCase()];
  return [
    internalLoginEmailForName(value),
    legacyInternalLoginEmailForName(value),
  ];
}
