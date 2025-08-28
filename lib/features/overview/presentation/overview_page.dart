import 'package:flutter/material.dart';
import '../../contracts/data/app_state.dart';
import '../../contracts/domain/models.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routes.dart' as r;

class OverviewPage extends StatefulWidget {
  final AppState state;
  const OverviewPage({super.key, required this.state});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  // month vs year toggle
  bool _showYearly = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final contracts = widget.state.contracts.where((c) => c.isActive && !c.isDeleted).toList();
        final categories = widget.state.categories;
        if (contracts.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Overview')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No contracts yet'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.push(r.AppRoutes.contracts),
                    child: const Text('Add a contract'),
                  ),
                ],
              ),
            ),
          );
        }

        // Cost aggregation helpers
        double monthlyCostFor(Contract c) {
          final amount = c.costAmount;
          final cycle = c.billingCycle;
          if (amount == null || cycle == null) return 0;
          switch (cycle) {
            case BillingCycle.monthly:
              return amount;
            case BillingCycle.quarterly:
              return amount / 3.0;
            case BillingCycle.yearly:
              return amount / 12.0;
            case BillingCycle.oneTime:
              return 0; // exclude one-time from recurring totals
          }
          // Fallback (should be unreachable with enum switch)
          return 0;
        }
        final totalMonthly = contracts.fold<double>(0, (sum, c) => sum + monthlyCostFor(c));
        final totalYearly = totalMonthly * 12.0;

        // Upcoming expirations (next 3)
        final now = DateTime.now();
        final upcoming = contracts
            .where((c) => !c.isOpenEnded && c.endDate != null && c.endDate!.isAfter(now))
            .toList()
          ..sort((a, b) => a.endDate!.compareTo(b.endDate!));
        final nextThree = upcoming.take(3).toList();

        // Category spending for pie
        final byCategory = <String, double>{};
        for (final c in contracts) {
          byCategory[c.categoryId] = (byCategory[c.categoryId] ?? 0) + monthlyCostFor(c);
        }

        final theme = Theme.of(context);
        final isLight = theme.brightness == Brightness.light;
        final spendTint = isLight ? theme.colorScheme.primary.withOpacity(0.06) : null;
        final expTint = isLight ? theme.colorScheme.tertiary.withOpacity(0.06) : null;
        final pieTint = isLight ? theme.colorScheme.secondary.withOpacity(0.06) : null;

        return Scaffold(
          appBar: AppBar(title: const Text('Overview')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Total spend card with month/year toggle
              Card(
                color: spendTint,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_showYearly ? 'Yearly spend' : 'Monthly spend',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(
                              _formatCurrency(_showYearly ? totalYearly : totalMonthly),
                              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Monthly')),
                          ButtonSegment(value: true, label: Text('Yearly')),
                        ],
                        selected: {_showYearly},
                        onSelectionChanged: (s) => setState(() => _showYearly = s.first),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Upcoming expirations
              Card(
                color: expTint,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.schedule_outlined),
                          const SizedBox(width: 8),
                          Text('Next expirations', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (nextThree.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('No upcoming expirations',
                              style: Theme.of(context).textTheme.bodyMedium),
                        )
                      else
                        ...nextThree.map((c) {
                          final cat = widget.state.categoryById(c.categoryId)!;
                          final days = c.endDate!.difference(now).inDays;
                          final urgency = days <= 7
                              ? Colors.red
                              : days <= 30
                                  ? Colors.orange
                                  : Colors.green;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(cat.icon),
                            title: Text(c.title),
                            subtitle: Text('${c.provider} • ends ${_fmtDate(c.endDate!)}'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: urgency.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('$days d', style: TextStyle(color: urgency, fontWeight: FontWeight.w600)),
                            ),
                            onTap: () => context.push(r.AppRoutes.contractDetails(c.id)),
                          );
                        }),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Pie chart for category spending (monthly share)
              Card(
                color: pieTint,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.pie_chart_outline),
                          const SizedBox(width: 8),
                          Text('Spending by category', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CategoryPieChart(
                        categories: categories,
                        values: byCategory,
                        onSliceTap: (catId) => context.push(r.AppRoutes.contracts, extra: catId),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatCurrency(double value) {
    // Lightweight currency formatting (no intl dependency)
    final v = value;
    final s = v.abs() >= 1000 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return '€ $s';
  }

  String _fmtDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }
}

// --- Pie Chart Widget (no external packages) ---
class CategoryPieChart extends StatefulWidget {
  final List<ContractGroup> categories;
  final Map<String, double> values; // categoryId -> monthly value
  final void Function(String categoryId) onSliceTap;
  const CategoryPieChart({super.key, required this.categories, required this.values, required this.onSliceTap});

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  String? _hovered; // for slight emphasis on hover/tap down (desktop)

  @override
  Widget build(BuildContext context) {
    final size = 200.0;
    final palette = _buildPalette(context);
    final total = widget.values.values.fold<double>(0, (a, b) => a + b);
    final slices = <_Slice>[];
    double start = -90; // start at top
    for (var i = 0; i < widget.categories.length; i++) {
      final cat = widget.categories[i];
      final value = widget.values[cat.id] ?? 0;
      if (value <= 0 || total <= 0) continue;
      final sweep = 360 * (value / total);
      slices.add(_Slice(
        categoryId: cat.id,
        label: cat.name,
        startAngle: start,
        sweepAngle: sweep,
        color: palette[i % palette.length],
      ));
      start += sweep;
    }

    return Column(
      children: [
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(d.globalPosition);
              final tappedId = _categoryAt(local, size, slices);
              if (tappedId != null) widget.onSliceTap(tappedId);
            },
            child: CustomPaint(
              size: Size.square(size),
              painter: _PiePainter(slices: slices, hovered: _hovered),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Legend
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: slices
              .map((s) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(s.label, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ))
              .toList(),
        ),
      ],
    );
  }

  List<Color> _buildPalette(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    if (isLight) {
      // Vibrant but balanced for light backgrounds
      return [
        Colors.blueAccent.shade400,
        Colors.pinkAccent.shade400,
        Colors.teal.shade600,
        Colors.amber.shade700,
        Colors.deepPurpleAccent.shade400,
        Colors.orangeAccent.shade400,
        Colors.indigo.shade500,
        Colors.cyan.shade700,
        Colors.lime.shade800,
      ].map((c) => c.withOpacity(0.95)).toList();
    } else {
      // Bright accents that pop on dark backgrounds
      return [
        Colors.lightBlueAccent.shade200,
        Colors.pinkAccent.shade200,
        Colors.tealAccent.shade200,
        Colors.amberAccent.shade200,
        Colors.deepPurpleAccent.shade200,
        Colors.orangeAccent.shade200,
        Colors.indigoAccent.shade200,
        Colors.cyanAccent.shade200,
        Colors.limeAccent.shade200,
      ].map((c) => c.withOpacity(1.0)).toList();
    }
  }

  String? _categoryAt(Offset local, double size, List<_Slice> slices) {
    final center = Offset(size / 2, size / 2);
    final v = local - center;
    final r = v.distance;
    final innerR = (size / 2) * 0.55;
    if (r < innerR || r > size / 2) return null; // donut hole and outside rim
    // Convert to degrees, 0 at +X, clockwise
    var deg = (v.direction * 180 / 3.1415926535);
    var angle = (-deg) % 360; // clockwise from +X
    if (angle < 0) angle += 360;
    for (final s in slices) {
      final a0 = (s.startAngle % 360 + 360) % 360;
      final a1 = (a0 + s.sweepAngle) % 360;
      final within = s.sweepAngle >= 360
          ? true
          : a0 <= a1
              ? (angle >= a0 && angle <= a1)
              : (angle >= a0 || angle <= a1);
      if (within) return s.categoryId;
    }
    return null;
  }
}

class _Slice {
  final String categoryId;
  final String label;
  final double startAngle; // degrees
  final double sweepAngle; // degrees
  final Color color;
  _Slice({required this.categoryId, required this.label, required this.startAngle, required this.sweepAngle, required this.color});
}

class _PiePainter extends CustomPainter {
  final List<_Slice> slices;
  final String? hovered;
  _PiePainter({required this.slices, this.hovered});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2;
    final innerR = radius * 0.55; // donut look
    final paint = Paint()..style = PaintingStyle.fill;

    for (final s in slices) {
      paint.color = s.color;
      final startRad = s.startAngle * 3.1415926535 / 180.0;
      final sweepRad = s.sweepAngle * 3.1415926535 / 180.0;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(Rect.fromCircle(center: center, radius: radius), startRad, sweepRad, false)
        ..close();
      // Create donut by subtracting inner circle
      final donut = Path.combine(
        PathOperation.difference,
        path,
        Path()..addOval(Rect.fromCircle(center: center, radius: innerR)),
      );
      canvas.drawPath(donut, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) => oldDelegate.slices != slices || oldDelegate.hovered != hovered;
}
