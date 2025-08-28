import 'dart:async';
import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../domain/models.dart';

class NotesCard extends StatefulWidget {
  final AppState state;
  final String contractId;
  const NotesCard({super.key, required this.state, required this.contractId});

  @override
  State<NotesCard> createState() => _NotesCardState();
}

class _NotesCardState extends State<NotesCard> {
  bool _expanded = false;
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSave(String text, Contract current) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      widget.state.updateContract(current.copyWith(notes: text));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final c = widget.state.contractById(widget.contractId);
        if (c == null) return const SizedBox.shrink();
        // Keep controller in sync when state changes externally
        if (_controller.text != (c.notes ?? '')) {
          _controller.text = c.notes ?? '';
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        }
        final chars = _controller.text.length;
        final editedAt = widget.state.lastNoteEditedAt(widget.contractId);
        final editedLabel = editedAt != null
            ? ' • Last edited ${_fmtShort(editedAt)}'
            : '';
        return Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Notes'),
                subtitle: Text((c.notes ?? '').isEmpty
                    ? 'Add notes to this contract'
                    : 'Tap to edit'),
                trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                onTap: () => setState(() => _expanded = !_expanded),
              ),
              if (_expanded) const Divider(height: 1),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: TextField(
                    controller: _controller,
                    minLines: 4,
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'Write notes…',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (txt) => _scheduleSave(txt, c),
                  ),
                ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('$chars characters$editedLabel',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _fmtShort(DateTime dt) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return 'today ${two(dt.hour)}:${two(dt.minute)}';
  }
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}
