import '../domain/models.dart';
import '../../../core/db/db_service.dart';
import '../../../core/cloud/sync_registry.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter/foundation.dart';

class ContractsSnapshot {
  final List<ContractGroup> categories;
  final List<Contract> contracts;
  ContractsSnapshot({required this.categories, required this.contracts});
}

class ContractsStore {
  Future<ContractsSnapshot?> load() async {
    final db = await DbService.instance.db;
    final catsRows = await db.query(
      'contract_groups',
      where: 'deleted = 0',
      orderBy: 'order_index ASC, updated_at ASC, name ASC',
    );
    final categories = catsRows
        .map((r) => ContractGroup(
              id: r['id'] as String,
              name: r['name'] as String,
              builtIn: ((r['built_in'] as int?) ?? 0) == 1,
              orderIndex: ((r['order_index'] as int?) ?? 0),
              iconKey: (r['icon'] as String?),
            ))
        .toList();
    // Load all contracts, including trashed ones; AppState filters views.
    final consRows = await db.query('contracts');
    final contracts = consRows.map((r) => _contractFromRow(r, categories)).toList();
    debugPrint('[DB] load() categories=${categories.length} contracts=${contracts.length}');
    if (categories.isEmpty && contracts.isEmpty) return null;
    return ContractsSnapshot(categories: categories, contracts: contracts);
  }

  Future<void> save(List<ContractGroup> categories, List<Contract> contracts) async {
    debugPrint('[DB] save(): begin cats=${categories.length} cons=${contracts.length}');
    final db = await DbService.instance.db;
    await db.transaction((txn) async {
      // Load current state
      final existingCatsRows = await txn.query('contract_groups');
      final existingCats = {for (final r in existingCatsRows) r['id'] as String: r};
      final nowTs = await DbService.instance.nextLamportTsTx(txn);

      // Upsert categories only (no implicit tombstoning here)
      final incomingCatIds = <String>{};
      for (var idx = 0; idx < categories.length; idx++) {
        final g = categories[idx];
        incomingCatIds.add(g.id);
        final prev = existingCats[g.id];
        int rev = ((prev?['rev'] as int?) ?? 0);
        final prevName = prev?['name'] as String?;
        final prevBuilt = ((prev?['built_in'] as int?) ?? 0) == 1;
        final prevDeleted = ((prev?['deleted'] as int?) ?? 0) == 1;
        final prevOrder = (prev?['order_index'] as int?) ?? 0;
        final prevIcon = prev?['icon'] as String?;
        final curOrder = g.orderIndex ?? idx;
        final changed = prev == null || prevName != g.name || prevBuilt != g.builtIn || prevDeleted || prevOrder != curOrder || prevIcon != g.iconKey;
        if (changed) rev += 1;
        await txn.insert(
          'contract_groups',
          {
            'id': g.id,
            'name': g.name,
            'built_in': g.builtIn ? 1 : 0,
            'order_index': curOrder,
            'icon': g.iconKey,
            'deleted': 0,
            'rev': rev,
            'updated_at': nowTs,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (changed) {
          final fields = SyncRegistry.instance.toFields('category', {
            'name': g.name,
            'built_in': g.builtIn,
            'order_index': curOrder,
            'icon': g.iconKey,
          });
          await DbService.instance.logOpTx(txn,
              entity: 'category', entityId: g.id, op: 'put', rev: rev, ts: nowTs, fields: fields);
        }
      }
      // Do not tombstone categories missing from the incoming list; explicit delete paths handle that.

      // Contracts
      final existingConsRows = await txn.query('contracts');
      final existingCons = {for (final r in existingConsRows) r['id'] as String: r};
      final incomingConIds = <String>{};
      for (final c in contracts) {
        incomingConIds.add(c.id);
        final prev = existingCons[c.id];
        int rev = ((prev?['rev'] as int?) ?? 0);
        final fields = SyncRegistry.instance.toFields('contract', _contractToRow(c));
        bool changed = false;
        if (prev == null) {
          changed = true;
        } else {
          // shallow compare selected fields
          for (final k in fields.keys) {
            if (k == 'rev' || k == 'updated_at') continue;
            final pv = prev[k];
            final nv = fields[k];
            if (pv != nv) { changed = true; break; }
          }
        }
        if (changed) rev += 1;
        await txn.insert('contracts', {...fields, 'rev': rev, 'updated_at': nowTs}, conflictAlgorithm: ConflictAlgorithm.replace);
        if (changed) {
          await DbService.instance.logOpTx(txn, entity: 'contract', entityId: c.id, op: c.isDeleted ? 'delete' : 'put', rev: rev, ts: nowTs, fields: fields);
        }
      }
      // Do not tombstone contracts missing from the incoming list; explicit delete paths handle that.
    });
    debugPrint('[DB] save() categories=${categories.length} contracts=${contracts.length}');
  }

  Future<void> tombstoneCategory(String id) async {
    final db = await DbService.instance.db;
    await db.transaction((txn) async {
      final cur = await txn.query('contract_groups', where: 'id = ?', whereArgs: [id], limit: 1);
      int prevRev = (cur.isNotEmpty ? (cur.first['rev'] as int?) : 0) ?? 0;
      final rev = prevRev + 1;
      final ts = await DbService.instance.nextLamportTsTx(txn);
      await txn.insert(
        'contract_groups',
        {
          'id': id,
          'name': cur.isNotEmpty ? cur.first['name'] : 'Deleted',
          'built_in': (cur.isNotEmpty ? (cur.first['built_in'] as int?) : 0) ?? 0,
          'order_index': (cur.isNotEmpty ? (cur.first['order_index'] as int?) : 0) ?? 0,
          'icon': cur.isNotEmpty ? cur.first['icon'] : null,
          'deleted': 1,
          'rev': rev,
          'updated_at': ts,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await DbService.instance.logOpTx(txn, entity: 'category', entityId: id, op: 'delete', rev: rev, ts: ts, fields: null);
    });
  }

  Map<String, dynamic> _contractToRow(Contract c) => {
        'id': c.id,
        'title': c.title,
        'provider': c.provider,
        'customer_number': c.customerNumber,
        'category_id': c.categoryId,
        'cost_amount': c.costAmount,
        'cost_currency': c.costCurrency,
        'billing_cycle': c.billingCycle?.name,
        'payment_method': c.paymentMethod?.name,
        'payment_note': c.paymentNote,
        'start_date': c.startDate?.millisecondsSinceEpoch,
        'end_date': c.endDate?.millisecondsSinceEpoch,
        'is_open_ended': c.isOpenEnded ? 1 : 0,
        'is_active': c.isActive ? 1 : 0,
        'is_deleted': c.isDeleted ? 1 : 0,
        'notes': c.notes,
        'deleted_at': c.deletedAt?.millisecondsSinceEpoch,
      };

  Contract _contractFromRow(Map<String, Object?> j, List<ContractGroup> cats) {
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
    final categoryId = (j['category_id'] as String?) ?? 'cat_other';
    final knownCat = cats.any((c) => c.id == categoryId);
    return Contract(
      id: (j['id'] as String?) ?? 'c_${DateTime.now().microsecondsSinceEpoch}',
      title: (j['title'] as String?) ?? 'Untitled',
      provider: (j['provider'] as String?) ?? '',
      customerNumber: j['customer_number'] as String?,
      categoryId: knownCat ? categoryId : 'cat_other',
      costAmount: (j['cost_amount'] as num?)?.toDouble(),
      costCurrency: (j['cost_currency'] as String?) ?? 'EUR',
      billingCycle: parseBilling(j['billing_cycle'] as String?),
      paymentMethod: parsePayment(j['payment_method'] as String?),
      paymentNote: j['payment_note'] as String?,
      startDate: fromMs(j['start_date'] as int?),
      endDate: fromMs(j['end_date'] as int?),
      isOpenEnded: ((j['is_open_ended'] as int?) ?? 0) == 1,
      isActive: ((j['is_active'] as int?) ?? 1) == 1,
      isDeleted: ((j['is_deleted'] as int?) ?? 0) == 1,
      notes: j['notes'] as String?,
      deletedAt: fromMs(j['deleted_at'] as int?),
    );
  }
}

