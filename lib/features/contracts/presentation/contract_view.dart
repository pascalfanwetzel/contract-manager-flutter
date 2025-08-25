import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/models.dart';
import '../data/app_state.dart';
import '../../../app/routes.dart' as r;
import 'widgets.dart';

class ContractView extends StatefulWidget {
  final AppState state;
  final Contract contract;
  const ContractView({super.key, required this.state, required this.contract});

  @override
  State<ContractView> createState() => _ContractViewState();
}

class _ContractViewState extends State<ContractView> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final c =
            widget.state.contractById(widget.contract.id) ?? widget.contract;
        final cat = widget.state.categoryById(c.categoryId)!;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Contract'),
            actions: [
              if (!c.isDeleted)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final updated = await context.push<Contract>(
                      r.AppRoutes.contractNew,
                      extra: c, // pass the current contract to edit
                    );
                    if (updated != null) {
                      widget.state.updateContract(updated);
                    }
                  },
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Chip(
                    label: Text(c.isActive ? 'Active' : 'Inactive'),
                    avatar: Icon(
                      c.isActive ? Icons.check_circle : Icons.close,
                      size: 18,
                      color: c.isActive ? null : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

          // Summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Provider', c.provider),
                  _kv('Category', cat.name),
                  _kv('Start', formatDate(c.startDate)),
                  _kv('End', c.isOpenEnded ? 'Open end' : formatDate(c.endDate)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Costs & payment
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Cost', formatMoney(c.costAmount, c.costCurrency)),
                  _kv('Interval', formatCycle(c.billingCycle)),
                  _kv('Payment', c.paymentMethod?.label ?? '—'),
                  if (c.paymentMethod == PaymentMethod.other &&
                      (c.paymentNote ?? '').isNotEmpty)
                    _kv('Payment details', c.paymentNote!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Attachments (placeholder)
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Attachments'),
              subtitle: const Text('Add PDFs/images via Edit (coming soon)'),
            ),
          ),
          const SizedBox(height: 12),

          // Notes (placeholder)
          Card(
            child: ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('Notes'),
              subtitle: const Text('Add notes to this contract (coming soon)'),
            ),
          ),
          const SizedBox(height: 24),

          if (!c.isDeleted)
            (c.isActive
                ? OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('End contract'),
                          content:
                              const Text('Mark this contract as ended today?'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('End')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        widget.state.updateContract(
                            c.copyWith(isActive: false, endDate: DateTime.now()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Contract ended')),
                        );
                      }
                    },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('End contract'),
                  )
                : FilledButton.icon(
                    onPressed: null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      disabledBackgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close),
                    label: const Text('Contract ended'),
                  )),
          const SizedBox(height: 8),

          if (!c.isDeleted)
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete contract'),
                    content: const Text('This cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  widget.state.deleteContract(c.id);
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  messenger.showSnackBar(
                    SnackBar(
                      content:
                          const Text('Deleted Contract moved to Trash'),
                      duration: const Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                      action: SnackBarAction(
                        label: '✕',
                        onPressed: () {
                          messenger.hideCurrentSnackBar();
                        },
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(
                k,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
