import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/models.dart';
import '../data/app_state.dart';
import 'widgets.dart';
import 'category_actions.dart';
import '../../../app/routes.dart' as r;

class ContractsPage extends StatefulWidget {
  final AppState state;
  final String? initialCategoryId;
  const ContractsPage({super.key, required this.state, this.initialCategoryId});

  @override
  State<ContractsPage> createState() => _ContractsPageState();
}

class _ContractsPageState extends State<ContractsPage> {
  final _q = TextEditingController();
  String? _selectedCategoryId; // null == All
  String? _editingCategoryId;

  @override
  void initState() {
    super.initState();
    // Preselect category if provided via navigation
    _selectedCategoryId = widget.initialCategoryId;
  }

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
        if (widget.state.isLoading) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Contracts'),
              actions: [
                IconButton(
                  tooltip: 'Manage categories',
                  icon: const Icon(Icons.tune),
                  onPressed: null,
                ),
              ],
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final categories = [...widget.state.categories];
        categories.sort((a, b) {
          if (a.id == 'cat_other') return 1;
          if (b.id == 'cat_other') return -1;
          return 0;
        });
        if (_selectedCategoryId != null &&
            !categories.any((c) => c.id == _selectedCategoryId)) {
          _selectedCategoryId = null;
        }
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
          ),
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _editingCategoryId = null),
            child: Padding(
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
                        final newC = await context.push<Contract>(r.AppRoutes.contractNew);
                        if (newC != null) widget.state.addContract(newC);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Category chips + New category
                SingleChildScrollView(clipBehavior: Clip.none, 
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _selectedCategoryId == null,
                        onSelected: (_) => setState(() {
                          _selectedCategoryId = null;
                          _editingCategoryId = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      ...categories.map(
                        (cat) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: CategoryChip(
                            category: cat,
                            selected: _selectedCategoryId == cat.id,
                            editing: _editingCategoryId == cat.id,
                            onSelected: () => setState(() {
                              _selectedCategoryId = cat.id;
                              _editingCategoryId = null;
                            }),
                            onDelete: () async {
                              await deleteCategoryWithFallbackFlow(
                                context,
                                state: widget.state,
                                category: cat,
                                onDone: (fallbackId, moved) {
                                  if (_selectedCategoryId == cat.id) {
                                    _selectedCategoryId = fallbackId;
                                  }
                                  setState(() => _editingCategoryId = null);
                                },
                              );
                            },
                            onRename: () async {
                              await renameCategoryFlow(
                                context,
                                state: widget.state,
                                category: cat,
                              );
                              setState(() => _editingCategoryId = null);
                            },
                            onLongPress: () => setState(() => _editingCategoryId = cat.id),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.add),
                        label: const Text('New category'),
                        onPressed: () async {
                          final name = await promptForTextDialog(
                            context,
                            title: 'New category',
                            hint: 'e.g. Insurance',
                          );
                          if (name != null && name.trim().isNotEmpty) {
                            final id = widget.state.addCategory(name.trim());
                            setState(() => _selectedCategoryId = id);
                          }
                          setState(() => _editingCategoryId = null);
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
                          separatorBuilder: (context, _) =>
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
          ),
        );
      },
    );
  }

  // promptForText moved to category_actions.dart to avoid duplicates
}

