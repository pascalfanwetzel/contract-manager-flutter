import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../contracts/data/providers.dart';
import 'package:go_router/go_router.dart';

class ContractsListPage extends ConsumerWidget {
  const ContractsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncContracts = ref.watch(contractsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Contracts')),
      body: asyncContracts.when(
        data: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) {
            final c = items[i];
            return ListTile(
              title: Text(c.title),
              subtitle: Text(c.provider),
              onTap: () => context.push('/contracts/${c.id}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => ref.read(contractsRepoProvider).delete(c.id),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/contracts/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
