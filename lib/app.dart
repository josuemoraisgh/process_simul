import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/constants/app_theme.dart';
import 'presentation/screens/main_shell.dart';
import 'presentation/screens/hart_table/hart_table_screen.dart';
import 'presentation/screens/modbus_table/modbus_table_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/logs/logs_screen.dart';

final _router = GoRouter(
  initialLocation: '/hart',
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/hart',
          builder: (_, __) => const HartTableScreen(),
        ),
        GoRoute(
          path: '/modbus',
          builder: (_, __) => const ModbusTableScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/logs',
          builder: (_, __) => const LogsScreen(),
        ),
      ],
    ),
  ],
);

class ProcessSimulApp extends ConsumerWidget {
  const ProcessSimulApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ProcessSimul',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
