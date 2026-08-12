import 'package:encba_locker/features/auth/presentation/auth_gate.dart';
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [GoRoute(path: '/', builder: (context, state) => const AuthGate())],
);
