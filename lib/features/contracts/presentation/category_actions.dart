import 'package:flutter/material.dart';
import '../data/app_state.dart';
import '../domain/models.dart';

Future<String?> promptForTextDialog(
  BuildContext context, {
  required String title,
  required String hint,
  String? initialText,
  String confirmLabel = 'Save',
}) async {
  final ctrl = TextEditingController(text: initialText ?? '');
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
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

class _CategoryDialogResult {
  final String name;
  final String? iconKey;
  _CategoryDialogResult(this.name, this.iconKey);
}

Future<String?> _chooseIconDialog(BuildContext context, {String? initialIconKey}) async {
  String? selected = initialIconKey;
  final keys = kCategoryIconMap.keys.toList();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Choose Icon'),
        content: SizedBox(
          width: 500,
          height: 320,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: keys.length,
            itemBuilder: (_, i) {
              final k = keys[i];
              final icon = kCategoryIconMap[k]!;
              final sel = selected == k;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => selected = k),
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        color: sel ? Theme.of(ctx).colorScheme.secondaryContainer : Theme.of(ctx).colorScheme.surface,
                        border: Border.all(color: sel ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).dividerColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: Icon(icon)),
                    ),
                    if (sel)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.check, size: 14, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('Done')),
        ],
      ),
    ),
  );
}

Future<_CategoryDialogResult?> _editCategorySheet(
  BuildContext context, {
  required String title,
  String? initialName,
  String? initialIconKey,
  String confirmLabel = 'Save',
}) async {
  final nameCtl = TextEditingController(text: initialName ?? '');
  String? iconKey = initialIconKey;
  return showModalBottomSheet<_CategoryDialogResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'Category name'),
                autofocus: true,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListTile(
                leading: Icon(iconKey == null ? Icons.category_outlined : kCategoryIconMap[iconKey!]),
                title: const Text('Icon'),
                // No subtitle: avoid exposing internal icon key names to users
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final chosen = await _chooseIconDialog(ctx, initialIconKey: iconKey);
                  if (chosen != null) {
                    iconKey = chosen;
                    (ctx as Element).markNeedsBuild();
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      final n = nameCtl.text.trim();
                      if (n.isEmpty) { Navigator.pop(ctx); return; }
                      Navigator.pop(ctx, _CategoryDialogResult(n, iconKey));
                    },
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> renameCategoryFlow(
  BuildContext context, {
  required AppState state,
  required ContractGroup category,
}) async {
  final res = await _editCategorySheet(context, title: 'Edit category', initialName: category.name, initialIconKey: category.iconKey);
  if (res == null) return;
  if (res.name != category.name) {
    final norm = res.name.trim().toLowerCase();
    final exists = state.categories.any((c) => c.id != category.id && c.name.trim().toLowerCase() == norm);
    if (exists) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(content: Text('A category with this name already exists')));
    } else {
      state.renameCategory(category.id, res.name);
    }
  }
  if (res.iconKey != category.iconKey) {
    state.updateCategoryMeta(category.id, iconKey: res.iconKey);
  }
}

Future<String?> _pickFallbackCategorySheet(
  BuildContext context, {
  required AppState state,
  required ContractGroup deleting,
  required List<ContractGroup> choices,
}) async {
  String selected = choices.first.id;
  final movedCount = state.contracts.where((c) => c.categoryId == deleting.id).length;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          const itemHeight = 56.0;
          const headerHeight = 48.0;
          const actionsHeight = 56.0;
          final media = MediaQuery.of(ctx);
          final visibleCount = (choices.length < 5) ? choices.length : 5;
          final desired = headerHeight + actionsHeight + visibleCount * itemHeight;
          final maxH = media.size.height * 0.9;
          final listHeight = (desired > maxH ? maxH : desired) - (headerHeight + actionsHeight);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Delete category', style: Theme.of(ctx).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Move ${movedCount == 0 ? 'all' : movedCount.toString()} contract${movedCount == 1 ? '' : 's'} to:'),
          ),
          SizedBox(
            height: listHeight,
            child: RadioGroup<String>(
              groupValue: selected,
              onChanged: (v) {
                if (v != null) {
                  selected = v;
                  (ctx as Element).markNeedsBuild();
                }
              },
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...choices.map((c) => RadioListTile<String>(
                        value: c.id,
                        title: Text(c.name),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ),
        ],
          );
        },
      ),
    ),
  );
}

Future<void> deleteCategoryWithFallbackFlow(
  BuildContext context, {
  required AppState state,
  required ContractGroup category,
  void Function(String fallbackId, int moved)? onDone,
}) async {
  // Capture messenger before async gaps to avoid context-after-await lint
  final messenger = ScaffoldMessenger.of(context);
  // Build fallback choices; exclude the deleting id. If empty, create one.
  final others = state.categories.where((x) => x.id != category.id).toList();
  if (others.isEmpty) {
    final id = state.addCategory('General');
    final created = state.categories.firstWhere((e) => e.id == id);
    others.add(created);
  }
  final fallbackId = await _pickFallbackCategorySheet(context, state: state, deleting: category, choices: others);
  if (fallbackId == null) return;
  final moved = state.deleteCategoryWithFallback(category.id, fallbackId);
  onDone?.call(fallbackId, moved);
  messenger.showSnackBar(
    SnackBar(
      content: Text('$moved contract${moved == 1 ? '' : 's'} moved'),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: '✕',
        onPressed: () => messenger.hideCurrentSnackBar(),
      ),
    ),
  );
}

Future<String?> newCategoryFlow(BuildContext context, {required AppState state}) async {
  final res = await _editCategorySheet(context, title: 'New category', confirmLabel: 'Create');
  if (res == null || res.name.trim().isEmpty) return null;
  final name = res.name.trim();
  final norm = name.toLowerCase();
  final exists = state.categories.any((c) => c.name.trim().toLowerCase() == norm);
  if (exists) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Category name must be unique')));
    return null;
  }
  final id = state.addCategory(name);
  if (res.iconKey != null) {
    state.updateCategoryMeta(id, iconKey: res.iconKey);
  }
  return id;
}

