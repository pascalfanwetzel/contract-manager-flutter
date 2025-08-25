import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/models.dart';
import '../data/app_state.dart';
import 'widgets.dart';
import '../../../app/routes.dart' as r;

class ContractsPage extends StatefulWidget {
  final AppState state;
  const ContractsPage({super.key, required this.state});

  @override
  State<ContractsPage> createState() => _ContractsPageState();
}

class _ContractsPageState extends State<ContractsPage> {
  final _q = TextEditingController();
  String? _selectedCategoryId; // null == All

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
        final categories = widget.state.categories;
        final all = widget.state.contracts;

        final query = _q.text.trim().toLowerCase();
        final filtered = all.where((c) {
          final matchQ = query.isEmpty ||
              c.title.toLowerCase().contains(query) ||
              c.provider.toLowerCase().contains(query);
          final matchCat =
              _selectedCategoryId == null || c.categoryId == _selectedCategoryId;
          return matchQ && matchCat;
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Contracts'),
            actions: [
              IconButton(
                tooltip: 'Manage categories',
                icon: const Icon(Icons.tune),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _ManageCategoriesDialog(state: widget.state),
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _q,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Search contracts…',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final newC =
                            await context.push<Contract>(r.AppRoutes.contractNew);
                        if (newC != null) widget.state.addContract(newC);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Category chips + New category
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _selectedCategoryId == null,
                        onSelected: (_) =>
                            setState(() => _selectedCategoryId = null),
                      ),
                      const SizedBox(width: 8),
                      ...categories.map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              avatar: Icon(cat.icon, size: 18),
                              label: Text(cat.name),
                              selected: _selectedCategoryId == cat.id,
                              onSelected: (_) =>
                                  setState(() => _selectedCategoryId = cat.id),
                            ),
                          )),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.add),
                        label: const Text('New category'),
                        onPressed: () async {
                          final name = await _promptForText(
                            context,
                            title: 'New category',
                            hint: 'e.g. Insurance',
                          );
                          if (name != null && name.trim().isNotEmpty) {
                            final id = widget.state.addCategory(name.trim());
                            setState(() => _selectedCategoryId = id);
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No contracts'))
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            final cat =
                                widget.state.categoryById(c.categoryId)!;
                            return ContractTile(
                              contract: c,
                              category: cat,
                              onDetails: () async {
                                await context.push(
                                  r.AppRoutes.contractDetails(c.id),
                                );
                                // state is a ChangeNotifier; UI will rebuild via AnimatedBuilder
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _promptForText(
    BuildContext context, {
    required String title,
    required String hint,
  }) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// Manage categories dialog (rename/delete custom groups)
class _ManageCategoriesDialog extends StatefulWidget {
  final AppState state;
  const _ManageCategoriesDialog({required this.state});
  @override
  State<_ManageCategoriesDialog> createState() =>
      _ManageCategoriesDialogState();
}

class _ManageCategoriesDialogState extends State<_ManageCategoriesDialog> {
  @override
  Widget build(BuildContext context) {
    final cats = widget.state.categories;
    return AlertDialog(
      title: const Text('Manage categories'),
      content: SizedBox(
        width: 360,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: cats.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final cat = cats[i];
            return ListTile(
              leading: Icon(cat.icon),
              title: Text(cat.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Rename',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final ctrl = TextEditingController(text: cat.name);
                      final newName = await showDialog<String>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Rename category'),
                          content:
                              TextField(controller: ctrl, autofocus: true),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(
                                    context, ctrl.text.trim()),
                                child: const Text('Save')),
                          ],
                        ),
                      );
                      if (newName != null && newName.isNotEmpty) {
                        widget.state.renameCategory(cat.id, newName);
                        setState(() {});
                      }
                    },
                  ),
                  IconButton(
                    tooltip:
                        cat.builtIn ? 'Cannot delete default' : 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: cat.builtIn
                        ? null
                        : () {
                            widget.state.deleteCategory(cat.id);
                            setState(() {});
                          },
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}
