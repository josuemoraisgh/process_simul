import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../application/providers/app_providers.dart';
import '../widgets/comm_bar_widget.dart';
import 'tank_3d/tank_3d_screen.dart' show isFullscreenNotifier;

class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    (icon: Icons.view_in_ar, label: '3D', path: '/tank3d'),
    (icon: Icons.table_chart_outlined, label: 'HART', path: '/hart'),
    (icon: Icons.settings_ethernet, label: 'Modbus', path: '/modbus'),
    (icon: Icons.tune, label: 'Settings', path: '/settings'),
    (icon: Icons.receipt_long_outlined, label: 'Logs', path: '/logs'),
  ];

  void _onDestination(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    context.go(_destinations[index].path);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isFullscreenNotifier,
      builder: (context, isFullscreen, _) {
        if (isFullscreen) {
          return Scaffold(body: widget.child);
        }

        final isWide = MediaQuery.sizeOf(context).width >= 720;

        return Scaffold(
          appBar: _buildAppBar(context),
          body: Column(
            children: [
              const CommBarWidget(),
              Expanded(
                child: isWide
                    ? Row(children: [
                        _buildNavRail(),
                        const VerticalDivider(width: 1),
                        Expanded(child: widget.child),
                      ])
                    : widget.child,
              ),
            ],
          ),
          bottomNavigationBar: isWide ? null : _buildNavBar(),
        );
      },
    );
  }

  AppBar _buildAppBar(BuildContext context) => AppBar(
        title: Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.developer_board,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          const Text('ProcessSimul'),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('HART/Modbus',
                style: TextStyle(fontSize: 11, color: AppColors.primaryLight)),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined, size: 20),
            tooltip: 'Reload table',
            onPressed: () => ref.read(hartTableProvider.notifier).load(),
          ),
          const SizedBox(width: 4),
        ],
      );

  NavigationRail _buildNavRail() => NavigationRail(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestination,
        labelType: NavigationRailLabelType.all,
        minWidth: 72,
        destinations: _destinations
            .map((d) => NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ))
            .toList(),
      );

  NavigationBar _buildNavBar() => NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestination,
        destinations: _destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  label: d.label,
                ))
            .toList(),
      );
}
