import 'dart:async';

import 'package:encba_locker/core/config/app_config.dart';
import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/locker/services/notification_category_prefs.dart';
import 'package:encba_locker/features/locker/services/notification_history_service.dart';
import 'package:encba_locker/features/locker/services/web_notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _notificationEnabledKey = 'encba.notifications.enabled.v1';

@pragma('vm:entry-point')
Future<void> encbaFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = PushNotificationService.firebaseOptions;
  if (options == null) return;
  await Firebase.initializeApp(options: options);
}

/// FCM token lifecycle and the existing local-notification fallback.
///
/// Firebase configuration is optional so local development and deployments
/// that have not completed `flutterfire configure` keep their previous
/// notification behavior instead of failing at startup.
class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  GoRouter? _router;
  String? _pendingPath;
  bool _initialized = false;

  static FirebaseOptions? get firebaseOptions {
    if (!AppConfig.hasFirebaseBase) return null;
    final String appId;
    if (kIsWeb) {
      appId = AppConfig.firebaseWebAppId;
    } else {
      appId = switch (defaultTargetPlatform) {
        TargetPlatform.android => AppConfig.firebaseAndroidAppId,
        TargetPlatform.iOS => AppConfig.firebaseIosAppId,
        _ => '',
      };
    }
    if (appId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: AppConfig.firebaseApiKey,
      appId: appId,
      messagingSenderId: AppConfig.firebaseMessagingSenderId,
      projectId: AppConfig.firebaseProjectId,
      iosBundleId: defaultTargetPlatform == TargetPlatform.iOS &&
              AppConfig.firebaseIosBundleId.isNotEmpty
          ? AppConfig.firebaseIosBundleId
          : null,
    );
  }

  bool get supportsRemotePush => firebaseOptions != null;

  Future<bool> initialize() async {
    if (_initialized) return supportsRemotePush;
    final options = firebaseOptions;
    if (options == null) return false;
    try {
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(
        encbaFirebaseMessagingBackgroundHandler,
      );
      _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
          .listen((token) => unawaited(_registerToken(token)));
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        // 제목에 앱 이름을 쓰면 브라우저·OS가 붙이는 앱 이름과 겹쳐
        // "ENCBA LOCKER from LOCKER"처럼 보인다.
        final title = notification.title ?? '새 알림';
        final body = notification.body ?? '';
        unawaited(NotificationHistoryService().add(title: title, body: body));
        unawaited(WebNotificationService().show(title, body));
      });
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
      );
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) _handleOpenedMessage(initialMessage);
      _initialized = true;
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA Firebase initialization skipped: $error\n$stackTrace');
      return false;
    }
  }

  void attachRouter(GoRouter router) {
    _router = router;
    final path = _pendingPath;
    if (path == null) return;
    _pendingPath = null;
    router.go(path);
  }

  Future<bool> enableAndTest() async {
    if (!await initialize()) return WebNotificationService().enableAndTest();
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return false;
    final token = await _currentToken();
    if (token == null || token.isEmpty) return false;
    await LocalStore().setString(_notificationEnabledKey, 'true');
    await _registerToken(token);
    await WebNotificationService().show(
      '원격 알림이 켜졌습니다',
      '긴급 공지와 출결 마감을 알려드릴게요.',
    );
    return true;
  }

  Future<bool> isEnabled() async =>
      await LocalStore().getString(_notificationEnabledKey) == 'true';

  Future<void> disable() async {
    await LocalStore().setString(_notificationEnabledKey, 'false');
    if (!supportsRemotePush) {
      await WebNotificationService().disable();
      return;
    }
    final token = await _currentToken();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (token == null || userId == null) return;
    await Supabase.instance.client
        .from('push_subscriptions')
        .update({'enabled': false})
        .eq('profile_id', userId)
        .eq('fcm_token', token);
  }

  Future<void> updateCategories(
    Map<NotificationCategory, bool> categories,
  ) async {
    if (!supportsRemotePush || !await isEnabled()) return;
    final token = await _currentToken();
    if (token == null) return;
    await _registerToken(
      token,
      categories: [
        for (final entry in categories.entries)
          if (entry.value) entry.key.name,
      ],
    );
  }

  Future<String?> _currentToken() => FirebaseMessaging.instance.getToken(
    vapidKey: kIsWeb && AppConfig.firebaseVapidKey.isNotEmpty
        ? AppConfig.firebaseVapidKey
        : null,
  );

  Future<void> _registerToken(
    String token, {
    List<String>? categories,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || token.isEmpty) return;
    final enabledCategories = categories ??
        [
          for (final category in NotificationCategory.values)
            if (await NotificationCategoryPrefs().isEnabled(category))
              category.name,
        ];
    await Supabase.instance.client.from('push_subscriptions').upsert({
      'profile_id': userId,
      'fcm_token': token,
      'platform': _platformName,
      'categories': enabledCategories,
      'enabled': true,
    }, onConflict: 'fcm_token');
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final path = message.data['path'];
    if (path is! String || !path.startsWith('/')) return;
    final router = _router;
    if (router == null) {
      _pendingPath = path;
    } else {
      router.go(path);
    }
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'web',
    };
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}
