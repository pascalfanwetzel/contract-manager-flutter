import 'package:flutter/material.dart';
import '../../../contracts/data/app_state.dart';

class TrashView extends StatefulWidget {
  final AppState state;
  const TrashView({super.key, required this.state});

  @override
  State<TrashView> createState() => _TrashViewState();
}

class _TrashViewState extends State<TrashView> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final all = widget.state.trashedContracts;
        final query = _q.text.trim().toLowerCase();
        final filtered = all.where((c) {
          final matchQ = query.isEmpty ||
              c.title.toLowerCase().contains(query) ||
              c.provider.toLowerCase().contains(query);
          return matchQ;
        }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _q,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search deleted contracts…',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: all.isEmpty
                        ? null
                        : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Empty trash?'),
                                content: const Text(
                                    'Permanently delete all trashed contracts?'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              widget.state.purgeAll();
                            }
                          },
                    child: const Text('Delete all'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  return ListTile(
                    title: Text(c.title),
                    subtitle: Text(c.provider),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
