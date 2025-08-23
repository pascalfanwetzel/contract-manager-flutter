import 'package:flutter/material.dart';
import '../../contracts/data/app_state.dart';

class RemindersPage extends StatelessWidget {
  final AppState state;
  const RemindersPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Configure rules like “14 days before end date” (coming soon)'),
        ),
      ),
    );
  }
}
