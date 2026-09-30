import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-navigation shell for the four main tabs:
///
/// HOME · PURCHASES · MY STUFF · DEADLINES
///
/// Hosted by a go_router [StatefulShellRoute]; each branch keeps its own
/// navigation stack so tab state survives switching.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<_Tab> _tabs = [
    _Tab(label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home),
    _Tab(
      label: 'Purchases',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
    ),
    _Tab(
      label: 'My Stuff',
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
    ),
    _Tab(
      label: 'Deadlines',
      icon: Icons.event_outlined,
      activeIcon: Icons.event,
    ),
  ];

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      // Tapping the active tab pops back to its root.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.activeIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}
