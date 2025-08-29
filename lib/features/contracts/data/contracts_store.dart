import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';
import '../../../core/crypto/app_crypto.dart';

class ContractsSnapshot {
  final List<ContractGroup> categories;
  final List<Contract> contracts;
  ContractsSnapshot({required this.categories, required this.contracts});
}

class ContractsStore {
  Future<File> _plainFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/contracts.json');
  }

  Future<File> _encFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/contracts.enc');
  }

  Future<ContractsSnapshot?> load() async {
    // Prefer encrypted file; fall back to plaintext for migration
    try {
      final ef = await _encFile();
      if (await ef.exists()) {
        final sealed = await ef.readAsBytes();
        final bytes = await AppCrypto.decryptBytes(Uint8List.fromList(sealed), domain: 'contracts');
        final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final catsJ = (j['categories'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
        final consJ = (j['contracts'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
        final categories = catsJ.map(_catFromJson).toList();
        final contracts = consJ.map((m) => _contractFromJson(m, categories)).toList();
        return ContractsSnapshot(categories: categories, contracts: contracts);
      }
    } catch (_) {
      // If decrypt fails, try plaintext as a last resort
    }
    try {
      final pf = await _plainFile();
      if (!await pf.exists()) return null;
      final txt = await pf.readAsString();
      if (txt.trim().isEmpty) return null;
      final j = jsonDecode(txt) as Map<String, dynamic>;
      final catsJ = (j['categories'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
      final consJ = (j['contracts'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
      final categories = catsJ.map(_catFromJson).toList();
      final contracts = consJ.map((m) => _contractFromJson(m, categories)).toList();
      // Migrate to encrypted file
      await save(categories, contracts);
      // Optionally delete plaintext to reduce leakage
      try { await pf.delete(); } catch (_) {}
      return ContractsSnapshot(categories: categories, contracts: contracts);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<ContractGroup> categories, List<Contract> contracts) async {
    final ef = await _encFile();
    final data = {
      'categories': categories.map(_catToJson).toList(),
      'contracts': contracts.map(_contractToJson).toList(),
    };
    final bytes = utf8.encode(jsonEncode(data));
    final sealed = await AppCrypto.encryptBytes(Uint8List.fromList(bytes), domain: 'contracts');
    await ef.writeAsBytes(sealed, flush: true);
  }

  // --- Serialization helpers ---
  Map<String, dynamic> _catToJson(ContractGroup g) => {
        'id': g.id,
        'name': g.name,
        'builtIn': g.builtIn,
      };
  ContractGroup _catFromJson(Map<String, dynamic> j) => ContractGroup(
        id: (j['id'] as String?) ?? 'cat_${DateTime.now().microsecondsSinceEpoch}',
        name: (j['name'] as String?) ?? 'Category',
        builtIn: (j['builtIn'] as bool?) ?? false,
      );

  Map<String, dynamic> _contractToJson(Contract c) => {
        'id': c.id,
        'title': c.title,
        'provider': c.provider,
        'customerNumber': c.customerNumber,
        'categoryId': c.categoryId,
        'costAmount': c.costAmount,
        'costCurrency': c.costCurrency,
        'billingCycle': c.billingCycle?.name,
        'paymentMethod': c.paymentMethod?.name,
        'paymentNote': c.paymentNote,
        'startDate': c.startDate?.millisecondsSinceEpoch,
        'endDate': c.endDate?.millisecondsSinceEpoch,
        'isOpenEnded': c.isOpenEnded,
        'isActive': c.isActive,
        'isDeleted': c.isDeleted,
        'notes': c.notes,
        'deletedAt': c.deletedAt?.millisecondsSinceEpoch,
      };

  Contract _contractFromJson(Map<String, dynamic> j, List<ContractGroup> cats) {
    BillingCycle? parseBilling(String? s) => switch (s) {
          'monthly' => BillingCycle.monthly,
          'quarterly' => BillingCycle.quarterly,
          'yearly' => BillingCycle.yearly,
          'oneTime' => BillingCycle.oneTime,
          _ => null,
        };
    PaymentMethod? parsePayment(String? s) => switch (s) {
          'sepa' => PaymentMethod.sepa,
          'paypal' => PaymentMethod.paypal,
          'creditCard' => PaymentMethod.creditCard,
          'bankTransfer' => PaymentMethod.bankTransfer,
          'other' => PaymentMethod.other,
          _ => null,
        };
    DateTime? fromMs(int? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    final categoryId = (j['categoryId'] as String?) ?? 'cat_other';
    final knownCat = cats.any((c) => c.id == categoryId);
    return Contract(
      id: (j['id'] as String?) ?? 'c_${DateTime.now().microsecondsSinceEpoch}',
      title: (j['title'] as String?) ?? 'Untitled',
      provider: (j['provider'] as String?) ?? '',
      customerNumber: j['customerNumber'] as String?,
      categoryId: knownCat ? categoryId : 'cat_other',
      costAmount: (j['costAmount'] as num?)?.toDouble(),
      costCurrency: (j['costCurrency'] as String?) ?? 'EUR',
      billingCycle: parseBilling(j['billingCycle'] as String?),
      paymentMethod: parsePayment(j['paymentMethod'] as String?),
      paymentNote: j['paymentNote'] as String?,
      startDate: fromMs(j['startDate'] as int?),
      endDate: fromMs(j['endDate'] as int?),
      isOpenEnded: (j['isOpenEnded'] as bool?) ?? false,
      isActive: (j['isActive'] as bool?) ?? true,
      isDeleted: (j['isDeleted'] as bool?) ?? false,
      notes: j['notes'] as String?,
      deletedAt: fromMs(j['deletedAt'] as int?),
    );
  }
}
