import 'package:flutter/material.dart';
import '../../contracts/data/app_state.dart';

class ProfilePage extends StatelessWidget {
  final AppState state;
  const ProfilePage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('User settings, legal, help, and logout (coming soon)'),
        ),
      ),
    );
  }
}
