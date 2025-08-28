import 'package:flutter/material.dart';
import '../../../contracts/data/app_state.dart';

class SettingsView extends StatelessWidget {
  final AppState state;
  const SettingsView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final theme = state.themeMode;
        final grid = state.attachmentsGridPreferred;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Appearance', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    groupValue: theme,
                    title: const Text('Use system theme'),
                    onChanged: (v) => state.setThemeMode(v!),
                  ),
                  const Divider(height: 1),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    groupValue: theme,
                    title: const Text('Light mode'),
                    onChanged: (v) => state.setThemeMode(v!),
                  ),
                  const Divider(height: 1),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    groupValue: theme,
                    title: const Text('Dark mode'),
                    onChanged: (v) => state.setThemeMode(v!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Attachments', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: SwitchListTile(
                title: const Text('Default to grid view'),
                subtitle: const Text('Use a grid layout when viewing attachments'),
                value: grid,
                onChanged: (v) => state.setAttachmentsGridPreferred(v),
              ),
            ),
          ],
        );
      },
    );
  }
}
