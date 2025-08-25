import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/contracts/data/app_state.dart';
import 'routes.dart';

class HomeShell extends StatelessWidget {
  final AppState state;
  final Widget child; // current routed page
  const HomeShell({super.key, required this.state, required this.child});

    int _indexFromLocation(String loc) {
      if (loc.startsWith(AppRoutes.contracts)) return 1;
      if (loc.startsWith(AppRoutes.profile)) return 2;
      return 0; // overview default
    }

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    final idx = _indexFromLocation(loc);
      final paths = const [
        AppRoutes.overview,
        AppRoutes.contracts,
        AppRoutes.profile,
      ];

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => context.go(paths[i]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Overview',
            ),
            NavigationDestination(
              icon: Icon(Icons.description_outlined),
              selectedIcon: Icon(Icons.description),
              label: 'Contracts',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
      ),
    );
  }
}
