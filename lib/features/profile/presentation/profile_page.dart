import 'package:flutter/material.dart';
import '../../contracts/data/app_state.dart';
import 'views/user_info_view.dart';
import 'views/notifications_view.dart';
import 'views/privacy_view.dart';
import 'data_storage/data_storage_page.dart';

class ProfilePage extends StatelessWidget {
  final AppState state;
  const ProfilePage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'User Info'),
              Tab(text: 'Notifications & Reminders'),
              Tab(text: 'Privacy'),
              Tab(text: 'Data & Storage'),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  const UserInfoView(),
                  const NotificationsView(),
                  const PrivacyView(),
                  DataStoragePage(state: state),
                ],
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Column(
                children: [
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
            ),
          ],
        ),
      ),
    );
  }
}
