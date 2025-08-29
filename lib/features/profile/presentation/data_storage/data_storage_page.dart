import 'package:flutter/material.dart';
import '../../../contracts/data/app_state.dart';
import 'trash_view.dart';

class DataStoragePage extends StatelessWidget {
  final AppState state;
  const DataStoragePage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: SafeArea(
        child: Column(
          children: [
            // Auto-empty trash controls
            AnimatedBuilder(
              animation: state,
              builder: (context, _) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Auto-empty Trash'),
                            subtitle: const Text('Permanently delete items after a retention period'),
                            value: state.autoEmptyTrashEnabled,
                            onChanged: (v) => state.setAutoEmptyTrashEnabled(v),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Retention:'),
                              const SizedBox(width: 12),
                              DropdownButton<int>(
                                value: state.autoEmptyTrashDays,
                                items: const [
                                  DropdownMenuItem(value: 7, child: Text('7 days')),
                                  DropdownMenuItem(value: 30, child: Text('30 days')),
                                  DropdownMenuItem(value: 60, child: Text('60 days')),
                                  DropdownMenuItem(value: 90, child: Text('90 days')),
                                ],
                                onChanged: state.autoEmptyTrashEnabled
                                    ? (v) {
                                        if (v != null) state.setAutoEmptyTrashDays(v);
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // Reset to demo dataset
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.refresh_outlined),
                  title: const Text('Reset to demo data'),
                  subtitle: const Text('Replace your contracts with sample demo items'),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Reset to demo data?'),
                        content: const Text('This will replace your current contracts with a sample dataset.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await state.resetToDemoData();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Demo data restored')),
                        );
                      }
                    }
                  },
                ),
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Trash / Recently Deleted'),
              ],
            ),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  TrashView(state: state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
