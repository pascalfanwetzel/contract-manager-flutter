import 'package:flutter/material.dart';
import '../domain/models.dart';

class ContractTile extends StatelessWidget {
  final Contract contract;
  final ContractGroup category;
  final VoidCallback onDetails;

  const ContractTile({
    super.key,
    required this.contract,
    required this.category,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final status = contract.isExpired ? 'Expired' : 'Active';
    final statusColor = contract.isExpired
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer;

    return Card(
      child: ListTile(
        leading: Icon(category.icon),
        title: Text(contract.title),
        subtitle: Text('${contract.provider} • ${category.name}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(status),
        ),
        onTap: onDetails,
      ),
    );
  }
}

// helpers
String formatMoney(double? amount, String currency) {
  if (amount == null) return '—';
  return '$currency ${amount.toStringAsFixed(2)}';
}

String formatCycle(BillingCycle? c) => c?.label ?? '—';

String formatDate(DateTime? d) => d == null
    ? '—'
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
