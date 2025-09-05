import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../contracts/data/app_state.dart';
import '../../../../core/auth/auth_service.dart';

class ProfilePage extends StatelessWidget {
  final AppState state;
  const ProfilePage({super.key, required this.state});

  void _openSectionRoute(BuildContext context, String route) {
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    const tilePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
              ListTile(
                contentPadding: tilePadding,
                leading: const Icon(Icons.person_outline),
                title: const Text('User Information'),
                onTap: () => _openSectionRoute(context, '/profile/user'),
              ),
              ListTile(
                contentPadding: tilePadding,
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () => _openSectionRoute(context, '/profile/settings'),
              ),
              ListTile(
                contentPadding: tilePadding,
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications & Reminders'),
                onTap: () => _openSectionRoute(context, '/profile/notifications'),
              ),
              // Swapped order: Data & Storage before Privacy
              ListTile(
                contentPadding: tilePadding,
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Data & Storage'),
                onTap: () => _openSectionRoute(context, '/profile/storage'),
              ),
              ListTile(
                contentPadding: tilePadding,
                leading: const Icon(Icons.lock_outline),
                title: const Text('Privacy'),
                onTap: () => _openSectionRoute(context, '/profile/privacy'),
              ),
              // Moved actions directly under Privacy
              ListTile(
                contentPadding: tilePadding,
                leading: const Icon(Icons.help_outline),
                title: const Text('Help & Feedback'),
                onTap: () => _openSectionRoute(context, '/profile/help'),
              ),
              ListTile(
                contentPadding: tilePadding,
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () {
                  // Sign out and return to welcome via router redirect
                  AuthService.instance.signOut();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signed out')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
