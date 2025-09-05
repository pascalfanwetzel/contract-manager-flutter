import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../domain/models.dart';

/// Reusable widgets and formatting helpers for contract UI.

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
      final theme = Theme.of(context);
      final isLight = theme.brightness == Brightness.light;
      final subtleTint = isLight ? theme.colorScheme.primary.withValues(alpha: 0.06) : null;
      final status = contract.isActive
          ? (contract.isExpired ? 'Expired' : 'Active')
          : 'Inactive';
      final statusColor = contract.isActive
          ? (contract.isExpired
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.secondaryContainer)
          : theme.colorScheme.errorContainer;

    return Card(
      color: subtleTint,
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

class CategoryChip extends StatefulWidget {
  final ContractGroup category;
  final bool selected;
  final bool editing;
  final VoidCallback onSelected;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onLongPress;

  const CategoryChip({
    super.key,
    required this.category,
    required this.selected,
    required this.editing,
    required this.onSelected,
    this.onDelete,
    this.onRename,
    this.onLongPress,
  });

  @override
  State<CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<CategoryChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    if (widget.editing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant CategoryChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing != oldWidget.editing) {
      if (widget.editing) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final selectedColor = isLight
        ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.9)
        : theme.colorScheme.secondaryContainer;
    final chip = FilterChip(
      avatar: Icon(widget.category.icon, size: 18),
      label: Text(widget.category.name),
      selected: widget.selected,
      showCheckmark: false,
      selectedColor: selectedColor,
      onSelected: (_) => widget.onSelected(),
    );

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Transform.rotate(
          angle: widget.editing ? _jiggleAngle(_controller.value) : 0,
          child: child,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            chip,
            if (widget.editing && widget.onRename != null)
              Positioned(
                left: -4,
                top: -4,
                child: InkWell(
                  onTap: widget.onRename,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.edit, size: 20, color: Colors.white),
                  ),
                ),
              ),
            if (widget.editing && widget.onDelete != null)
              Positioned(
                right: -4,
                top: -4,
                child: InkWell(
                  onTap: widget.onDelete,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.close, size: 20, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _jiggleAngle(double t) {
    // t in [0,1), make a short pulse at the start, then rest
    if (t < 0.2) {
      final phase = (t / 0.2) * (2 * math.pi);
      return math.sin(phase) * 0.015; // ~0.86°
    }
    return 0.0;
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
