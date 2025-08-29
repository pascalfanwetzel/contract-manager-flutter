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
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('Theme'),
                      const SizedBox(height: 8),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_outlined)),
                          ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                        ],
                        selected: {theme},
                        onSelectionChanged: (s) => state.setThemeMode(s.first),
                        showSelectedIcon: false,
                      ),
                    ],
                  ),
                ),
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
