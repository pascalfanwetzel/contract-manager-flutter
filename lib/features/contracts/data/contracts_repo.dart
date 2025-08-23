import '../domain/contract.dart';

abstract class ContractsRepo {
  Stream<List<Contract>> watchAll();
  Future<String> add(Contract c);
  Future<void> update(Contract c);
  Future<void> delete(String id);
  Future<Contract?> getById(String id);
}
