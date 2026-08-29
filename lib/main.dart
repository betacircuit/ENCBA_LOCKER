import 'dart:async';

import 'package:encba_locker/core/config/app_config.dart';
import 'package:encba_locker/core/platform/url_strategy.dart';
import 'package:flutter/material.dart';
import 'package:encba_locker/core/widgets/gentle_scroll_behavior.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/core/routing/app_router.dart';
import 'package:encba_locker/features/locker/services/push_notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 주소를 경로로 쓴다. Supabase.initialize보다 먼저 불러야 OAuth
  // 리디렉트로 돌아온 주소를 해시 전략이 먼저 건드리지 않는다.
  useEncbaUrlStrategy();
  if (!AppConfig.hasSupabase) {
    runApp(const _ConfigurationMissingApp());
    return;
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );
  // 푸시 초기화(Firebase 시작·초기 메시지 확인)는 첫 화면을 가로막지 않는다.
  // 여기를 기다리면 서버와 무관한 준비 작업 때문에 앱 실행이 늦어졌다.
  unawaited(PushNotificationService.instance.initialize());
  runApp(const EncbaLockerApp());
}

class _ConfigurationMissingApp extends StatelessWidget {
  const _ConfigurationMissingApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ENCBA LOCKER',
    theme: AppTheme.lightTheme,
    debugShowCheckedModeBanner: false,
    locale: const Locale('ko', 'KR'),
    supportedLocales: const [Locale('ko', 'KR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'SUPABASE_URL과 SUPABASE_PUBLISHABLE_KEY가 필요합니다.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}

class EncbaLockerApp extends StatelessWidget {
  const EncbaLockerApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const ProviderScope(child: _RoutedApp());
}

class _RoutedApp extends ConsumerWidget {
  const _RoutedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // routerProvider는 내부에서 watch하지 않으므로 한 번만 만들어진다.
    final router = ref.watch(routerProvider);
    PushNotificationService.instance.attachRouter(router);
    return MaterialApp.router(
      title: 'ENCBA LOCKER',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const GentleScrollBehavior(),
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        // 당겨서 새로고침은 뺐다.
        //
        // 표시를 감춘 뒤로는 손짓이 걸려도 아무것도 안 보이는데 뒤에서는
        // 전체 데이터를 다시 받아, 화면이 끊기고 흔들리는 것처럼만 보였다.
        // 뒤로가기 손짓처럼 가로로 밀 때도 세로 성분이 조금만 섞이면
        // 걸려서 특히 성가셨다. 새로고침이 필요하면 상단 동기화 띠의
        // '다시 시도'로 명시적으로 한다.
        final refreshableChild = DefaultTextStyle.merge(
          style: const TextStyle(fontFamilyFallback: encbaFontFallback),
          child: child,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) return refreshableChild;

            final frameHeight = constraints.maxHeight > 900
                ? 900.0
                : constraints.maxHeight;
            return ColoredBox(
              color: const Color(0xFFE9EEF5),
              child: Center(
                child: Container(
                  width: 430,
                  height: frameHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFFD4DAE5)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26002856),
                        blurRadius: 44,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(size: Size(430, frameHeight)),
                    child: refreshableChild,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
