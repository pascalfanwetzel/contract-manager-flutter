import 'dart:io';
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
      bottomNavigationBar: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          return NavigationBar(
            selectedIndex: idx,
            onDestinationSelected: (i) => context.go(paths[i]),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Overview',
              ),
              const NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description),
                label: 'Contracts',
              ),
              NavigationDestination(
                icon: _profileTabIcon(state, selected: false),
                selectedIcon: _profileTabIcon(state, selected: true),
                label: 'Profile',
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _profileTabIcon(AppState state, {required bool selected}) {
  final p = state.profile;
  final hasPhoto = (p.photoPath != null && p.photoPath!.isNotEmpty && File(p.photoPath!).existsSync());
  final double radius = 12; // fits nicely in NavigationBar
  final avatar = CircleAvatar(
    radius: radius,
    backgroundColor: selected ? Colors.blueGrey.shade100 : Colors.grey.shade300,
    backgroundImage: hasPhoto ? FileImage(File(p.photoPath!)) : null,
    child: hasPhoto
        ? null
        : (p.name.trim().isEmpty
            ? Icon(Icons.person, size: 16, color: Colors.grey.shade800)
            : Text(
                p.initials,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              )),
  );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: avatar,
  );
}
