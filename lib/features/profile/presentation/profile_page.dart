import 'package:flutter/material.dart';
import '../../contracts/data/app_state.dart';
import 'views/user_info_view.dart';
import 'views/notifications_view.dart';
import 'views/privacy_view.dart';
import 'data_storage/data_storage_page.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('User Info'),
            onTap: () => _openSection(context, 'User Info', const UserInfoView()),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications & Reminders'),
            onTap: () => _openSection(
                context, 'Notifications & Reminders', const NotificationsView()),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Privacy'),
            onTap: () => _openSection(context, 'Privacy', const PrivacyView()),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Data & Storage'),
            onTap: () =>
                _openSection(context, 'Data & Storage', DataStoragePage(state: state)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & Feedback'),
            onTap: () {
              // TODO: navigate to help/feedback screen
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              // TODO: implement sign out
            },
          ),
        ],
      ),
    );
  }
}
