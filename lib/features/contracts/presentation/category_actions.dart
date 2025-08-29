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

Future<void> renameCategoryFlow(
  BuildContext context, {
  required AppState state,
  required ContractGroup category,
}) async {
  final newName = await promptForTextDialog(
    context,
    title: 'Rename category',
    hint: 'Enter new name',
    initialText: category.name,
    confirmLabel: 'Save',
  );
  if (newName == null || newName.isEmpty || newName == category.name) return;
  state.renameCategory(category.id, newName);
}

Future<String?> _pickFallbackCategoryDialog(
  BuildContext context, {
  required List<ContractGroup> choices,
}) async {
  String selected = choices.first.id;
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Choose fallback category'),
      content: StatefulBuilder(
        builder: (ctx, setState) => DropdownButton<String>(
          value: selected,
          isExpanded: true,
          items: choices
              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
              .toList(),
          onChanged: (v) => setState(() => selected = v ?? selected),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('Move & delete')),
      ],
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
  final fallbackId = await _pickFallbackCategoryDialog(context, choices: others);
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
