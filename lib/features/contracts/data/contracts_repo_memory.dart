import 'dart:async';
import 'package:uuid/uuid.dart';
import '../domain/contract.dart';
import 'contracts_repo.dart';

class ContractsRepoMemory implements ContractsRepo {
  final _uuid = const Uuid();
  final _items = <Contract>[];
  final _controller = StreamController<List<Contract>>.broadcast();

  ContractsRepoMemory() {
    _emit();
  }

  void _emit() => _controller.add(List.unmodifiable(_items));

  @override
  Stream<List<Contract>> watchAll() => _controller.stream;

  @override
  Future<String> add(Contract c) async {
    final id = _uuid.v4();
    _items.add(Contract(id: id, title: c.title, provider: c.provider, endDate: c.endDate));
    _emit();
    return id;
  }

  @override
  Future<void> update(Contract c) async {
    final i = _items.indexWhere((e) => e.id == c.id);
    if (i != -1) _items[i] = c;
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _items.removeWhere((e) => e.id == id);
    _emit();
  }

  @override
  Future<Contract?> getById(String id) async {
   final i = _items.indexWhere((e) => e.id == id);
  return i == -1 ? null : _items[i];
  }

}
