import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../contracts/data/app_state.dart';
import '../../../contracts/presentation/widgets.dart';
import '../../../../app/routes.dart' as r;

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
                              builder: (ctx) => AlertDialog(
                                title: const Text('Empty trash?'),
                                content: const Text(
                                    'Permanently delete all trashed contracts?'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              if (!mounted) return;
                              widget.state.purgeAll();
                            }
                          },
                    child: const Text('Delete all'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No trashed contracts'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        final cat =
                            widget.state.categoryById(c.categoryId)!;
                        return ContractTile(
                          contract: c,
                          category: cat,
                          onDetails: () =>
                              context.push(r.AppRoutes.contractDetails(c.id)),
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
