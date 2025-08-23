import 'package:flutter/foundation.dart';
import '../domain/models.dart';

class AppState extends ChangeNotifier {
  final List<ContractGroup> _categories = [
    const ContractGroup(id: 'cat_home', name: 'Home', builtIn: true),
    const ContractGroup(id: 'cat_subs', name: 'Subscriptions', builtIn: true),
    const ContractGroup(id: 'cat_other', name: 'Other', builtIn: true),
  ];

  final List<Contract> _contracts = [
    Contract(
      id: 'c1',
      title: 'Electricity',
      provider: 'GreenPower GmbH',
      categoryId: 'cat_home',
      costAmount: 62.90,
      costCurrency: '€',
      billingCycle: BillingCycle.monthly,
      paymentMethod: PaymentMethod.sepa,
      startDate: DateTime.now().subtract(const Duration(days: 120)),
      endDate: DateTime.now().add(const Duration(days: 240)),
    ),
    Contract(
      id: 'c2',
      title: 'Netflix',
      provider: 'Netflix',
      categoryId: 'cat_subs',
      costAmount: 12.99,
      costCurrency: '€',
      billingCycle: BillingCycle.monthly,
      paymentMethod: PaymentMethod.creditCard,
      isOpenEnded: true,
      startDate: DateTime.now().subtract(const Duration(days: 400)),
    ),
  ];

  // READ
  List<ContractGroup> get categories => List.unmodifiable(_categories);
  List<Contract> get contracts => List.unmodifiable(_contracts);
  ContractGroup? categoryById(String id) => _categories.firstWhere(
        (c) => c.id == id,
        orElse: () => const ContractGroup(id: 'cat_other', name: 'Other', builtIn: true),
      );

  // MUTATE
  void addContract(Contract c) {
    _contracts.add(c);
    notifyListeners();
  }

  void updateContract(Contract c) {
    final i = _contracts.indexWhere((e) => e.id == c.id);
    if (i != -1) {
      _contracts[i] = c;
      notifyListeners();
    }
  }

  void removeContract(String id) {
    _contracts.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  String addCategory(String name) {
    final id = 'cat_${DateTime.now().microsecondsSinceEpoch}';
    _categories.add(ContractGroup(id: id, name: name, builtIn: false));
    notifyListeners();
    return id;
  }

  void renameCategory(String id, String newName) {
    final i = _categories.indexWhere((c) => c.id == id);
    if (i != -1) {
      final old = _categories[i];
      _categories[i] = ContractGroup(id: old.id, name: newName, builtIn: old.builtIn);
      notifyListeners();
    }
  }

  void deleteCategory(String id) {
    if (_categories.any((c) => c.id == id && c.builtIn)) return; // keep defaults
    // move contracts to "Other" when their group is deleted
    for (final c in _contracts.where((c) => c.categoryId == id).toList()) {
      updateContract(c.copyWith(categoryId: 'cat_other'));
    }
    _categories.removeWhere((c) => c.id == id);
    notifyListeners();
  }
}
