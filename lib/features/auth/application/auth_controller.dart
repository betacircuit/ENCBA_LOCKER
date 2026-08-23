import 'dart:async';

import 'package:encba_locker/features/auth/data/supabase_auth_repository.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:encba_locker/core/storage/local_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class AuthState {
  const AuthState({
    this.isReady = false,
    this.isBusy = false,
    this.sessionRevision = 0,
    this.user,
    this.pendingRegistration,
    this.error,
  });

  final bool isReady;
  final bool isBusy;
  final int sessionRevision;
  final UserProfile? user;
  final PendingGoogleRegistration? pendingRegistration;
  final String? error;

  AuthState copyWith({
    bool? isReady,
    bool? isBusy,
    int? sessionRevision,
    UserProfile? user,
    bool clearUser = false,
    PendingGoogleRegistration? pendingRegistration,
    bool clearPendingRegistration = false,
    String? error,
    bool clearError = false,
  }) => AuthState(
    isReady: isReady ?? this.isReady,
    isBusy: isBusy ?? this.isBusy,
    sessionRevision: sessionRevision ?? this.sessionRevision,
    user: clearUser ? null : user ?? this.user,
    pendingRegistration: clearPendingRegistration
        ? null
        : pendingRegistration ?? this.pendingRegistration,
    error: clearError ? null : error ?? this.error,
  );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState()) {
    _restore();
    _subscription = _repository?.authChanges.listen(_handleAuthChange);
  }

  AuthController.seeded(
    UserProfile? user, {
    PendingGoogleRegistration? pendingRegistration,
  }) : _repository = null,
       super(
         AuthState(
           isReady: true,
           user: user,
           pendingRegistration: pendingRegistration,
         ),
       );

  final SupabaseAuthRepository? _repository;
  StreamSubscription<supabase.AuthState>? _subscription;
  SupabaseAuthRepository get _repo =>
      _repository ?? (throw StateError('Seeded auth cannot persist changes.'));

  Future<void> _restore() async {
    final oauthError = _repo.pendingOAuthError();
    // 캐시된 프로필로 먼저 화면을 그린다. 서버 확인(세션 갱신·프로필 조회·
    // 사진 받기)은 그 뒤에 조용히 진행돼 첫 화면이 네트워크를 기다리지 않는다.
    final cachedId = _repo.currentUserId;
    if (cachedId != null) {
      final cached = await _repo.loadCachedProfile(cachedId);
      if (cached != null && mounted && state.user == null) {
        state = state.copyWith(
          isReady: true,
          user: cached,
          clearError: oauthError == null,
          error: oauthError,
        );
      }
    }
    try {
      final session = await _repo.restoreSession();
      state = state.copyWith(
        isReady: true,
        user: session.profile,
        clearUser: session.profile == null,
        pendingRegistration: session.pendingRegistration,
        clearPendingRegistration: session.pendingRegistration == null,
        // 인증이 실패한 채 돌아왔다면 그 사유를 화면에 남긴다.
        error: session.profile == null && session.pendingRegistration == null
            ? oauthError
            : null,
        clearError:
            oauthError == null ||
            session.profile != null ||
            session.pendingRegistration != null,
      );
    } on EncbaAuthException catch (error) {
      state = state.copyWith(
        isReady: true,
        clearUser: true,
        clearPendingRegistration: true,
        error: error.message,
      );
    } on Object {
      state = state.copyWith(
        isReady: true,
        clearUser: true,
        clearPendingRegistration: true,
        error: '저장된 로그인 정보를 복원하지 못했습니다.',
      );
    }
  }

  Future<bool> signIn(String email, String password) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final user = await _repo.signIn(email, password);
      state = state.copyWith(
        isReady: true,
        isBusy: false,
        user: user,
        clearPendingRegistration: true,
      );
      return true;
    } on EncbaAuthException catch (error) {
      state = state.copyWith(isBusy: false, error: error.message);
      return false;
    } on Object {
      state = state.copyWith(
        isBusy: false,
        error: '로그인 중 연결 문제가 발생했습니다. 다시 시도해 주세요.',
      );
      return false;
    }
  }

  Future<bool> signUp(UserProfile profile, String password) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final user = await _repo.signUp(profile: profile, password: password);
      state = state.copyWith(
        isReady: true,
        isBusy: false,
        user: user,
        clearPendingRegistration: true,
      );
      return true;
    } on EncbaAuthException catch (error) {
      state = state.copyWith(isBusy: false, error: error.message);
      return false;
    } on Object {
      state = state.copyWith(
        isBusy: false,
        error: '회원가입 중 연결 문제가 발생했습니다. 다시 시도해 주세요.',
      );
      return false;
    }
  }

  Future<bool> startGoogleSignIn({bool forSignUp = false}) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _repo.startGoogleSignIn(forSignUp: forSignUp);
      state = state.copyWith(isBusy: false);
      return true;
    } on EncbaAuthException catch (error) {
      state = state.copyWith(isBusy: false, error: error.message);
      return false;
    } on Object {
      state = state.copyWith(
        isBusy: false,
        error: 'Google 로그인을 시작하지 못했습니다. 다시 시도해 주세요.',
      );
      return false;
    }
  }

  Future<bool> completeGoogleRegistration(
    UserProfile profile, {
    required String password,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final user = await _repo.completeGoogleRegistration(
        profile,
        password: password,
      );
      state = state.copyWith(
        isReady: true,
        isBusy: false,
        user: user,
        clearPendingRegistration: true,
      );
      return true;
    } on EncbaAuthException catch (error) {
      state = state.copyWith(isBusy: false, error: error.message);
      return false;
    } on Object {
      state = state.copyWith(
        isBusy: false,
        error: '회원정보를 저장하지 못했습니다. 다시 시도해 주세요.',
      );
      return false;
    }
  }

  Future<void> cancelGoogleRegistration() async {
    await _repo.signOut();
    state = state.copyWith(
      clearUser: true,
      clearPendingRegistration: true,
      clearError: true,
    );
  }

  Future<bool> updateProfile(UserProfile profile) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final updated = await _repo.updateProfile(profile);
      state = state.copyWith(isBusy: false, user: updated);
      return true;
    } on EncbaAuthException catch (error) {
      state = state.copyWith(isBusy: false, error: error.message);
      return false;
    } on Object {
      state = state.copyWith(
        isBusy: false,
        error: '프로필 저장 중 연결 문제가 발생했습니다. 다시 시도해 주세요.',
      );
      return false;
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = state.copyWith(
      clearUser: true,
      clearPendingRegistration: true,
      clearError: true,
    );
  }

  Future<void> _handleAuthChange(supabase.AuthState event) async {
    if (event.event == supabase.AuthChangeEvent.signedOut) {
      state = state.copyWith(
        isReady: true,
        sessionRevision: state.sessionRevision + 1,
        clearUser: true,
        clearPendingRegistration: true,
        clearError: true,
      );
      return;
    }
    if (event.session?.user != null &&
        state.user?.id != event.session!.user.id) {
      try {
        final session = await _repo.refreshSessionState();
        state = state.copyWith(
          isReady: true,
          sessionRevision: state.sessionRevision + 1,
          user: session.profile,
          clearUser: session.profile == null,
          pendingRegistration: session.pendingRegistration,
          clearPendingRegistration: session.pendingRegistration == null,
          clearError: true,
        );
      } on EncbaAuthException catch (error) {
        state = state.copyWith(isReady: true, error: error.message);
      }
      return;
    }
    if (event.session != null) {
      state = state.copyWith(sessionRevision: state.sessionRevision + 1);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final authRepositoryProvider = Provider(
  (ref) =>
      SupabaseAuthRepository(supabase.Supabase.instance.client, LocalStore()),
);
final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref.watch(authRepositoryProvider)),
);
