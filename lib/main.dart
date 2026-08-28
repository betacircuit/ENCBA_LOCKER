import 'dart:async';

import 'package:encba_locker/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:encba_locker/core/widgets/gentle_scroll_behavior.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/core/routing/app_router.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/services/push_notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        // 목록 맨 위에서 아래로 당기면 새로고침한다. 앱 전체를 감싸 두어야
        // 탭 화면과 상세 화면 어디서든 같은 손짓이 통한다.
        final refreshableChild = RefreshIndicator(
          onRefresh: () => ref.read(lockerControllerProvider.notifier).reload(),
          color: EncbaColors.snuBlue,
          backgroundColor: Colors.white,
          displacement: 32,
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamilyFallback: encbaFontFallback),
            child: child,
          ),
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
