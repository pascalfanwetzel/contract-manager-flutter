import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../data/app_state.dart';
import 'widgets.dart';
import 'attachments_card.dart';
import 'contract_create_flow.dart';
import 'notes_card.dart';

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
                    final messenger = ScaffoldMessenger.of(context);
                    await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (ctx) => FractionallySizedBox(
                        heightFactor: 0.96,
                        child: ContractCreateFlow(state: widget.state, editing: c),
                      ),
                    );
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Changes saved'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
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
                  _kv('Customer No.', (c.customerNumber ?? '').isEmpty ? '—' : c.customerNumber!),
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

          // Attachments
          AttachmentsCard(state: widget.state, contractId: c.id),
          const SizedBox(height: 12),

          // Notes (expandable editor)
          NotesCard(state: widget.state, contractId: c.id),
          const SizedBox(height: 24),

          if (!c.isDeleted)
            (c.isActive
                ? (c.isExpired
                    ? Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                await showModalBottomSheet<bool>(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  showDragHandle: true,
                                  builder: (ctx) => FractionallySizedBox(
                                    heightFactor: 0.96,
                                    child: ContractCreateFlow(
                                      state: widget.state,
                                      editing: c,
                                      initialStep: 1, // Billing
                                      showRenewalPrompt: true,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.autorenew),
                              label: const Text('Renew'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('End contract'),
                                    content: const Text('Mark this contract as ended today?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                      FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('End')),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  widget.state.updateContract(c.copyWith(isActive: false, endDate: DateTime.now()));
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Contract ended')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: const Text('Terminate'),
                            ),
                          ),
                        ],
                      )
                    : OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('End contract'),
                              content: const Text('Mark this contract as ended today?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('End')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            widget.state.updateContract(c.copyWith(isActive: false, endDate: DateTime.now()));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Contract ended')),
                            );
                          }
                        },
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('End contract'),
                      ))
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
                  if (!context.mounted) return;
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
      },
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
