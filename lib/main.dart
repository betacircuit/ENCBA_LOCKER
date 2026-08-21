import 'package:encba_locker/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/core/routing/app_router.dart';
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
  await PushNotificationService.instance.initialize();
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
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final fontSafeChild = DefaultTextStyle.merge(
          style: const TextStyle(fontFamilyFallback: encbaFontFallback),
          child: child,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) return fontSafeChild;

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
                    child: fontSafeChild,
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
