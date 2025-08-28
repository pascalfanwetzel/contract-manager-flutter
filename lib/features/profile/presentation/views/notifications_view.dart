import 'package:flutter/material.dart';
import '../../../contracts/data/app_state.dart';

class NotificationsView extends StatelessWidget {
  final AppState state;
  const NotificationsView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final choices = const [1, 7, 14, 30];
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final enabled = state.remindersEnabled;
        final selected = state.reminderDays;
        final tod = state.reminderTime;
        final push = state.pushEnabled;
        final banner = state.inAppBannerEnabled;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Reminders', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Enable reminders'),
                    subtitle: const Text('Get notified before contract expiration'),
                    value: enabled,
                    onChanged: (v) => state.setRemindersEnabled(v),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    enabled: enabled,
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('Time of day'),
                    subtitle: Text(tod.format(context)),
                    onTap: !enabled
                        ? null
                        : () async {
                            final picked = await showTimePicker(context: context, initialTime: tod);
                            if (picked != null) state.setReminderTime(picked);
                          },
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Notify me'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final d in choices)
                              FilterChip(
                                label: Text('$d day${d == 1 ? '' : 's'} before'),
                                selected: selected.contains(d),
                                onSelected: enabled ? (_) => state.toggleReminderDay(d) : null,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Notification Type', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Push notifications'),
                    subtitle: const Text('Delivery via system notifications'),
                    value: push,
                    onChanged: enabled ? (v) => state.setPushEnabled(v) : null,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('In-app reminders'),
                    subtitle: const Text('Show banners inside the app'),
                    value: banner,
                    onChanged: enabled ? (v) => state.setInAppBannerEnabled(v) : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Tips', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Reminders apply to all contracts with an end date. You can change these defaults anytime. ',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
