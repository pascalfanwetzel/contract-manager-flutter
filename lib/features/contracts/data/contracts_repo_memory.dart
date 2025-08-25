import 'dart:async';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
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
    _items.add(
        Contract(
          id: id,
          title: c.title,
          provider: c.provider,
          categoryId: c.categoryId,
          costAmount: c.costAmount,
          costCurrency: c.costCurrency,
          billingCycle: c.billingCycle,
          paymentMethod: c.paymentMethod,
          paymentNote: c.paymentNote,
          startDate: c.startDate,
          endDate: c.endDate,
          isOpenEnded: c.isOpenEnded,
          isActive: c.isActive,
          isDeleted: c.isDeleted,
        ),
      );
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
    final i = _items.indexWhere((e) => e.id == id);
    if (i != -1) {
      final c = _items[i];
      _items[i] = c.copyWith(isActive: false, isDeleted: true);
      _emit();
    }
  }

  @override
  Future<Contract?> getById(String id) async {
   final i = _items.indexWhere((e) => e.id == id);
  return i == -1 ? null : _items[i];
  }

}
