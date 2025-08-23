import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'contracts_repo.dart';
import 'contracts_repo_memory.dart';
import '../domain/contract.dart';

final contractsRepoProvider = Provider<ContractsRepo>((ref) {
  return ContractsRepoMemory(); // later swap to Firestore implementation
});

final contractsListProvider = StreamProvider<List<Contract>>((ref) {
  return ref.watch(contractsRepoProvider).watchAll();
});
