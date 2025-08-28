import 'package:flutter/material.dart';
import '../../contracts/data/app_state.dart';
import 'views/user_info_view.dart';
import 'views/notifications_view.dart';
import 'views/privacy_view.dart';
import 'data_storage/data_storage_page.dart';
import 'views/settings_view.dart';
import 'views/help_feedback_view.dart';

class ProfilePage extends StatelessWidget {
  final AppState state;
  const ProfilePage({super.key, required this.state});

  void _openSection(BuildContext context, String title, Widget view) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: view),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const tilePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top section: main profile options
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ListTile(
                    contentPadding: tilePadding,
                    leading: const Icon(Icons.person_outline),
                    title: const Text('User Information'),
                    onTap: () =>
                        _openSection(context, 'User Information', UserInfoView(state: state)),
                  ),
                  ListTile(
                    contentPadding: tilePadding,
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Settings'),
                    onTap: () => _openSection(context, 'Settings', SettingsView(state: state)),
                  ),
                  ListTile(
                    contentPadding: tilePadding,
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Notifications & Reminders'),
                    onTap: () => _openSection(context, 'Notifications & Reminders',
                        NotificationsView(state: state)),
                  ),
                  // Swapped order: Data & Storage before Privacy
                  ListTile(
                    contentPadding: tilePadding,
                    leading: const Icon(Icons.storage_outlined),
                    title: const Text('Data & Storage'),
                    onTap: () => _openSection(
                        context, 'Data & Storage', DataStoragePage(state: state)),
                  ),
                  ListTile(
                    contentPadding: tilePadding,
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Privacy'),
                    onTap: () =>
                        _openSection(context, 'Privacy', PrivacyView(state: state)),
                  ),
                ],
              ),
            ),
            // Bottom section: sticky actions
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8).copyWith(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: tilePadding,
                      leading: const Icon(Icons.help_outline),
                      title: const Text('Help & Feedback'),
                      onTap: () {
                        _openSection(context, 'Help & Feedback', HelpFeedbackView(state: state));
                      },
                    ),
                    ListTile(
                      contentPadding: tilePadding,
                      leading: const Icon(Icons.logout),
                      title: const Text('Logout'),
                      onTap: () {
                        // TODO: implement sign out
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
