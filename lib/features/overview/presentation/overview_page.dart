import 'package:flutter/material.dart';
import '../../contracts/data/app_state.dart';
import '../../contracts/presentation/widgets.dart';
import '../../contracts/presentation/contract_view.dart';

class OverviewPage extends StatelessWidget {
  final AppState state;
  const OverviewPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final items = state.contracts;
        return Scaffold(
          appBar: AppBar(title: const Text('Overview')),
          body: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No contracts yet'),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Add via Contracts tab')),
                        ),
                        child: const Text('Add a contract'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = items[i];
                    final cat = state.categoryById(c.categoryId)!;
                    return ContractTile(
                      contract: c,
                      category: cat,
                      onDetails: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ContractView(state: state, contract: c),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
