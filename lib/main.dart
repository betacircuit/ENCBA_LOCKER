import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/core/routing/app_router.dart';

void main() {
  runApp(
    const ProviderScope(
      child: EncbaLockerApp(),
    ),
  );
}

class EncbaLockerApp extends StatelessWidget {
  const EncbaLockerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ENCBA LOCKER',
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
