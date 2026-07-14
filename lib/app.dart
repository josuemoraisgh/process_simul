import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/constants/app_theme.dart';
import 'presentation/screens/main_shell.dart';
import 'presentation/screens/tank_3d/tank_3d_screen.dart';
import 'presentation/screens/hart_table/hart_table_screen.dart';
import 'presentation/screens/modbus_table/modbus_table_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/logs/logs_screen.dart';

typedef AppRouteOverrides = Map<String, WidgetBuilder>;

GoRouter createAppRouter({AppRouteOverrides overrides = const {}}) => GoRouter(
      initialLocation: '/tank3d',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/tank3d',
              builder: (context, _) =>
                  overrides['/tank3d']?.call(context) ?? const Tank3dScreen(),
            ),
            GoRoute(
              path: '/hart',
              builder: (context, _) =>
                  overrides['/hart']?.call(context) ?? const HartTableScreen(),
            ),
            GoRoute(
              path: '/modbus',
              builder: (context, _) =>
                  overrides['/modbus']?.call(context) ??
                  const ModbusTableScreen(),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, _) =>
                  overrides['/settings']?.call(context) ??
                  const SettingsScreen(),
            ),
            GoRoute(
              path: '/logs',
              builder: (context, _) =>
                  overrides['/logs']?.call(context) ?? const LogsScreen(),
            ),
          ],
        ),
      ],
    );

final _router = createAppRouter();

class ProcessSimulApp extends ConsumerWidget {
  const ProcessSimulApp({super.key, this.routerConfig});

  final GoRouter? routerConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ProcessSimul',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: routerConfig ?? _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
