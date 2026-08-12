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
    this.user,
    this.error,
  });

  final bool isReady;
  final bool isBusy;
  final UserProfile? user;
  final String? error;

  AuthState copyWith({
    bool? isReady,
    bool? isBusy,
    UserProfile? user,
    bool clearUser = false,
    String? error,
    bool clearError = false,
  }) => AuthState(
    isReady: isReady ?? this.isReady,
    isBusy: isBusy ?? this.isBusy,
    user: clearUser ? null : user ?? this.user,
    error: clearError ? null : error ?? this.error,
  );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState()) {
    _restore();
    _subscription = _repository?.authChanges.listen(_handleAuthChange);
  }

  AuthController.seeded(UserProfile? user)
    : _repository = null,
      super(AuthState(isReady: true, user: user));

  final SupabaseAuthRepository? _repository;
  StreamSubscription<supabase.AuthState>? _subscription;
  SupabaseAuthRepository get _repo =>
      _repository ?? (throw StateError('Seeded auth cannot persist changes.'));

  Future<void> _restore() async {
    try {
      final user = await _repo.restoreSession();
      state = state.copyWith(isReady: true, user: user, clearError: true);
    } on Object {
      state = state.copyWith(
        isReady: true,
        clearUser: true,
        error: '저장된 로그인 정보를 복원하지 못했습니다.',
      );
    }
  }

  Future<bool> signIn(String email, String password) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final user = await _repo.signIn(email, password);
      state = state.copyWith(isReady: true, isBusy: false, user: user);
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
      state = state.copyWith(isReady: true, isBusy: false, user: user);
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
    state = state.copyWith(clearUser: true, clearError: true);
  }

  Future<void> _handleAuthChange(supabase.AuthState event) async {
    if (event.event == supabase.AuthChangeEvent.signedOut) {
      state = state.copyWith(isReady: true, clearUser: true, clearError: true);
      return;
    }
    if (event.session?.user != null &&
        state.user?.id != event.session!.user.id) {
      try {
        final profile = await _repo.refreshProfile();
        state = state.copyWith(isReady: true, user: profile, clearError: true);
      } on EncbaAuthException catch (error) {
        state = state.copyWith(isReady: true, error: error.message);
      }
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
