import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// import '../domain/models.dart';
import 'contract_create_flow.dart';
import '../data/app_state.dart';
import 'widgets.dart';
import 'category_actions.dart';
import '../../../app/routes.dart' as r;
import '../../../core/auth/auth_service.dart';
import '../../../core/cloud/snapshot_service.dart';

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
  bool _bootSyncTriggered = false;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _kickFirstSyncIfNeeded();
    });
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
        if (!_bootSyncTriggered) {
          _kickFirstSyncIfNeeded();
        }
        if (widget.state.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final categories = [...widget.state.categories];
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
          floatingActionButton: AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: FloatingActionButton.extended(
              onPressed: _showAddSheet,
              icon: const Icon(Icons.add),
              label: const Text('Add contract'),
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              if (!widget.state.cloudSyncEnabled) {
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(const SnackBar(content: Text('Cloud sync is disabled')));
                await Future.delayed(const Duration(milliseconds: 200));
                return;
              }
              await widget.state.syncNow();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _editingCategoryId = null),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: CustomScrollView(
                  slivers: [
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    snap: false,
                    toolbarHeight: 56,
                    scrolledUnderElevation: 0,
                    title: const Text('Contracts'),
                    actions: [
                      if (widget.state.cloudSyncEnabled)
                        Padding(
                          padding: const EdgeInsets.only(right: 8, top: 12),
                          child: _syncStatusTag(context, widget.state),
                        ),
                    ],
                  ),
                  // Sticky search
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyHeaderDelegate(
                      height: 64,
                      child: Container(
                        color: Theme.of(context).colorScheme.surface,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: SearchBar(
                          controller: _q,
                          hintText: 'Search contracts...',
                          leading: const Icon(Icons.search),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ),
                  // Sticky categories row (reorderable)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyHeaderDelegate(
                      height: 64,
                      child: Container(
                        color: Theme.of(context).colorScheme.surface,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
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
                              SizedBox(
                                height: 40,
                                child: ReorderableListView.builder(
                                  key: const PageStorageKey('categories_reorderable'),
                                  scrollDirection: Axis.horizontal,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  proxyDecorator: (child, index, animation) {
                                    // Remove default rectangular shadow during drag for round chips
                                    return Material(
                                      type: MaterialType.transparency,
                                      child: child,
                                    );
                                  },
                                  onReorderStart: (index) {
                                    setState(() => _editingCategoryId = categories[index].id);
                                  },
                                  onReorder: (oldIndex, newIndex) {
                                    if (newIndex > oldIndex) newIndex -= 1;
                                    if (newIndex == oldIndex) return;
                                    final dragged = categories[oldIndex];
                                    final lastIndex = categories.length - 1;
                                    final lastIsOther = categories.isNotEmpty && categories[lastIndex].id == 'cat_other';
                                    if (dragged.id == 'cat_other') return;
                                    if (lastIsOther && newIndex >= lastIndex) {
                                      newIndex = (lastIndex - 1).clamp(0, lastIndex);
                                    }
                                    widget.state.reorderCategory(dragged.id, newIndex);
                                    setState(() => _editingCategoryId = null);
                                  },
                                  itemCount: categories.length,
                                  itemBuilder: (ctx, index) {
                                    final cat = categories[index];
                                    return Padding(
                                      key: ValueKey(cat.id),
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ReorderableDelayedDragStartListener(
                                        index: index,
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
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              ActionChip(
                                avatar: const Icon(Icons.add),
                                label: const Text('New category'),
                                onPressed: () async {
                                  final id = await newCategoryFlow(context, state: widget.state);
                                  if (id != null) setState(() => _selectedCategoryId = id);
                                  setState(() => _editingCategoryId = null);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (filtered.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('No contracts')),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                      sliver: SliverList.separated(
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          final cat = widget.state.categoryById(c.categoryId)!;
                          return ContractTile(
                            contract: c,
                            category: cat,
                            onDetails: () async {
                              await context.push(
                                r.AppRoutes.contractDetails(c.id),
                              );
                            },
                          );
                        },
                        separatorBuilder: (context, _) => const SizedBox(height: 8),
                        itemCount: filtered.length,
                      ),
                    ),
                ],
              ),
            ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _kickFirstSyncIfNeeded() async {
    if (_bootSyncTriggered) return;
    final s = widget.state;
    final signedIn = AuthService.instance.currentUser != null;
    if (!signedIn) { _bootSyncTriggered = true; return; }
    if (!s.cloudSyncEnabled || !s.hasCloudDek) { _bootSyncTriggered = true; return; }
    if (s.lastSyncTs != null) { _bootSyncTriggered = true; return; }
    _bootSyncTriggered = true;
    s.beginFreshCloudHydrate();
    try { await SnapshotService.instance.hydrateFromLatestSnapshotIfFresh(); } catch (_) {}
    try { await s.syncNow(); } catch (_) {}
    try { await s.rehydrateAll(); } catch (_) {}
  }

  Widget _syncStatusTag(BuildContext context, AppState state) {
    const baseText = 'Sync';
    return FutureBuilder<bool>(
      future: state.hasPendingLocalOps(),
      builder: (context, snap) {
        final pending = snap.data ?? false;
        final hasError = state.lastSyncError != null;
        final hasEverSynced = state.lastSyncTs != null;
        final isHealthy = !pending && hasEverSynced && !hasError;

        final lightScheme = ColorScheme.fromSeed(seedColor: const Color(0xFFD5DEDD), brightness: Brightness.light);
        final Color bg = (state.isSyncing || isHealthy) ? lightScheme.primaryContainer : lightScheme.surfaceContainerHighest;
        final Color fg = (state.isSyncing || isHealthy) ? lightScheme.onPrimaryContainer : lightScheme.onSurfaceVariant;

        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: state.isSyncing ? 0 : 1,
                child: Text(
                  baseText,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
              if (state.isSyncing)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAddSheet() async {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('Create manually'),
              onTap: () async {
                Navigator.pop(ctx);
                await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (ctx2) => FractionallySizedBox(
                    heightFactor: 0.96,
                    child: ContractCreateFlow(state: widget.state),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Scan or import PDF'),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import from PDF coming soon')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('From template'),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Templates coming soon')));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  _StickyHeaderDelegate({required this.height, required this.child});
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
