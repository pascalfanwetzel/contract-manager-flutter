import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart' show DatabaseExecutor, ConflictAlgorithm;
import 'oplog_models.dart';

/// Adapter interface for mapping SyncOp entities to local DB writes.
abstract class SyncEntityAdapter {
  String get entity;
  Future<bool> apply(DatabaseExecutor txn, SyncOp op, String myId);
  Map<String, dynamic> toFields(Map<String, dynamic> source);
}

class SyncRegistry {
  SyncRegistry._();
  static final SyncRegistry instance = SyncRegistry._();

  final Map<String, SyncEntityAdapter> _adapters = {
    'category': _CategoryAdapter(),
    'settings': _SettingsAdapter(),
    'profile': _ProfileAdapter(),
    'contract': _ContractAdapter(),
    'attachment': _AttachmentAdapter(),
    'note': _NoteAdapter(),
  };

  SyncEntityAdapter? adapterFor(String entity) => _adapters[entity];

  Map<String, dynamic> toFields(String entity, Map<String, dynamic> source) {
    final a = adapterFor(entity);
    if (a == null) return source;
    return a.toFields(source);
  }
}

class _ContractAdapter implements SyncEntityAdapter {
  @override
  String get entity => 'contract';

  @override
  Future<bool> apply(DatabaseExecutor txn, SyncOp op, String myId) async {
    final cur = await txn.query('contracts', where: 'id = ?', whereArgs: [op.entityId], limit: 1);
    int curRev = 0;
    int curTs = 0;
    if (cur.isNotEmpty) {
      curRev = (cur.first['rev'] as int?) ?? 0;
      curTs = (cur.first['updated_at'] as int?) ?? 0;
    }
    if (!_lwwAccept(incomingRev: op.rev, incomingTs: op.ts, localRev: curRev, localTs: curTs, myId: myId, otherId: op.deviceId)) return false;
    if (op.op == 'delete' || op.op == 'purge') {
      if (cur.isEmpty) {
        await txn.insert('contracts', {
          'id': op.entityId,
          'title': (op.fields?['title'] as String?) ?? 'Deleted',
          'provider': (op.fields?['provider'] as String?) ?? '',
          'customer_number': op.fields?['customer_number'],
          'category_id': (op.fields?['category_id'] as String?) ?? 'cat_other',
          'is_open_ended': 1,
          'is_active': 0,
          'is_deleted': 1,
          'deleted_at': op.ts,
          'rev': op.rev,
          'updated_at': op.ts,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await txn.update('contracts', {
          'is_deleted': 1,
          'is_active': 0,
          'deleted_at': op.ts,
          'rev': op.rev,
          'updated_at': op.ts,
        }, where: 'id = ?', whereArgs: [op.entityId]);
      }
      if (op.op == 'purge') {
        final atts = await txn.query('attachments', where: 'contract_id = ?', whereArgs: [op.entityId]);
        for (final a in atts) {
          final bh = a['blob_hash'] as String?;
          await txn.delete('thumbs', where: 'attachment_id = ?', whereArgs: [a['id']]);
          await txn.delete('attachments', where: 'id = ?', whereArgs: [a['id']]);
          if (bh != null && bh.isNotEmpty) {
            final b = await txn.query('blobs', where: 'hash = ?', whereArgs: [bh], limit: 1);
            if (b.isNotEmpty) {
              final rc = ((b.first['refcount'] as int?) ?? 1) - 1;
              if (rc <= 0) {
                await txn.delete('blobs', where: 'hash = ?', whereArgs: [bh]);
              } else {
                await txn.update('blobs', {'refcount': rc}, where: 'hash = ?', whereArgs: [bh]);
              }
            }
          }
        }
        await txn.delete('notes', where: 'contract_id = ?', whereArgs: [op.entityId]);
        await txn.delete('contracts', where: 'id = ?', whereArgs: [op.entityId]);
      }
      return true;
    } else {
      if (op.fields == null) return false;
      final m = <String, Object?>{...op.fields!};
      m['id'] = op.entityId;
      m['rev'] = op.rev;
      m['updated_at'] = op.ts;
      await txn.insert('contracts', m, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    }
  }

  @override
  Map<String, dynamic> toFields(Map<String, dynamic> source) => Map<String, dynamic>.from(source);
}

class _AttachmentAdapter implements SyncEntityAdapter {
  @override
  String get entity => 'attachment';

  @override
  Future<bool> apply(DatabaseExecutor txn, SyncOp op, String myId) async {
    final cur = await txn.query('attachments', where: 'id = ?', whereArgs: [op.entityId], limit: 1);
    int curRev = 0;
    int curTs = 0;
    if (cur.isNotEmpty) {
      curRev = (cur.first['rev'] as int?) ?? 0;
      curTs = (cur.first['updated_at'] as int?) ?? 0;
    }
    if (!_lwwAccept(incomingRev: op.rev, incomingTs: op.ts, localRev: curRev, localTs: curTs, myId: myId, otherId: op.deviceId)) return false;
    if (op.op == 'delete') {
      final blobHash = cur.isNotEmpty ? cur.first['blob_hash'] as String? : null;
      await txn.update('attachments', {'deleted': 1, 'rev': op.rev, 'updated_at': op.ts}, where: 'id = ?', whereArgs: [op.entityId]);
      await txn.delete('thumbs', where: 'attachment_id = ?', whereArgs: [op.entityId]);
      if (blobHash != null && blobHash.isNotEmpty) {
        final b = await txn.query('blobs', where: 'hash = ?', whereArgs: [blobHash], limit: 1);
        if (b.isNotEmpty) {
          final rc = ((b.first['refcount'] as int?) ?? 1) - 1;
          if (rc <= 0) {
            await txn.delete('blobs', where: 'hash = ?', whereArgs: [blobHash]);
          } else {
            await txn.update('blobs', {'refcount': rc}, where: 'hash = ?', whereArgs: [blobHash]);
          }
        }
      }
      return true;
    } else {
      final m = <String, Object?>{};
      if (cur.isNotEmpty) {
        m.addAll(cur.first);
      }
      if (op.fields != null) {
        m.addAll(op.fields!);
      }
      m['id'] = op.entityId;
      m['contract_id'] = m['contract_id'] ?? (cur.isNotEmpty ? cur.first['contract_id'] : null);
      m['name'] = m['name'] ?? (cur.isNotEmpty ? cur.first['name'] : 'Unnamed');
      m['type'] = m['type'] ?? (cur.isNotEmpty ? cur.first['type'] : 'other');
      m['created_at'] = m['created_at'] ?? (cur.isNotEmpty ? cur.first['created_at'] : op.ts);
      m['blob_hash'] = m['blob_hash'] ?? (cur.isNotEmpty ? cur.first['blob_hash'] : null);
      m['deleted'] = 0;
      m['rev'] = op.rev;
      m['updated_at'] = op.ts;
      m['data'] = Uint8List(0);
      await txn.insert('attachments', m, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    }
  }

  @override
  Map<String, dynamic> toFields(Map<String, dynamic> source) => Map<String, dynamic>.from(source);
}

class _NoteAdapter implements SyncEntityAdapter {
  @override
  String get entity => 'note';

  @override
  Future<bool> apply(DatabaseExecutor txn, SyncOp op, String myId) async {
    final cur = await txn.query('notes', where: 'contract_id = ?', whereArgs: [op.entityId], limit: 1);
    int curTs = cur.isNotEmpty ? ((cur.first['updated_at'] as int?) ?? 0) : 0;
    if (op.ts <= curTs) return false;
    if (op.op == 'delete') {
      await txn.delete('notes', where: 'contract_id = ?', whereArgs: [op.entityId]);
      return true;
    } else {
      await txn.insert('notes', {
        'contract_id': op.entityId,
        'text': op.fields?['text'] ?? '',
        'updated_at': op.ts,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    }
  }

  @override
  Map<String, dynamic> toFields(Map<String, dynamic> source) => {
        'text': (source['text'] ?? '').toString(),
      };
}

class _CategoryAdapter implements SyncEntityAdapter {
  @override
  String get entity => 'category';

  @override
  Future<bool> apply(DatabaseExecutor txn, SyncOp op, String myId) async {
    final cur = await txn.query('contract_groups', where: 'id = ?', whereArgs: [op.entityId], limit: 1);
    int curRev = 0;
    int curTs = 0;
    if (cur.isNotEmpty) {
      curRev = (cur.first['rev'] as int?) ?? 0;
      curTs = (cur.first['updated_at'] as int?) ?? 0;
    }
    if (!_lwwAccept(incomingRev: op.rev, incomingTs: op.ts, localRev: curRev, localTs: curTs, myId: myId, otherId: op.deviceId)) return false;
    if (op.op == 'delete') {
      await txn.insert('contract_groups', {
        'id': op.entityId,
        'name': cur.isNotEmpty ? cur.first['name'] : 'Deleted',
        'built_in': (cur.isNotEmpty ? (cur.first['built_in'] as int?) : 0) ?? 0,
        'deleted': 1,
        'rev': op.rev,
        'updated_at': op.ts,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    } else {
      final fields = op.fields ?? const {};
      await txn.insert('contract_groups', {
        'id': op.entityId,
        'name': fields['name'] ?? (cur.isNotEmpty ? cur.first['name'] : 'Unnamed'),
        'built_in': (fields['built_in'] as int?) ?? (cur.isNotEmpty ? (cur.first['built_in'] as int?) : 0) ?? 0,
        'order_index': (fields['order_index'] as int?) ?? (cur.isNotEmpty ? (cur.first['order_index'] as int?) : 0) ?? 0,
        'icon': fields['icon'] ?? (cur.isNotEmpty ? cur.first['icon'] : null),
        'deleted': 0,
        'rev': op.rev,
        'updated_at': op.ts,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    }
  }

  @override
  Map<String, dynamic> toFields(Map<String, dynamic> source) {
    final name = (source['name'] ?? '').toString();
    final builtIn = source['built_in'];
    final built = builtIn is bool ? (builtIn ? 1 : 0) : (builtIn is num ? builtIn.toInt() : 0);
    final oiRaw = source['order_index'];
    final orderIndex = oiRaw is num ? oiRaw.toInt() : (oiRaw is String ? int.tryParse(oiRaw) ?? 0 : 0);
    final icon = source['icon'];
    return {
      'name': name,
      'built_in': built,
      'order_index': orderIndex,
      if (icon != null) 'icon': icon,
    };
  }
}

class _SettingsAdapter implements SyncEntityAdapter {
  @override
  String get entity => 'settings';

  @override
  Future<bool> apply(DatabaseExecutor txn, SyncOp op, String myId) async {
    if (op.fields == null) return false;
    final rows = await txn.query('settings', where: 'key = ?', whereArgs: ['settings_ts'], limit: 1);
    int localTs = 0;
    if (rows.isNotEmpty) {
      localTs = int.tryParse(rows.first['value'] as String? ?? '0') ?? 0;
    }
    if (op.ts <= localTs) return false;
    await txn.insert('settings', {
      'key': 'settings',
      'value': jsonEncode(op.fields),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert('settings', {'key': 'settings_ts', 'value': op.ts.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  @override
  Map<String, dynamic> toFields(Map<String, dynamic> source) {
    final out = Map<String, dynamic>.from(source);
    out.remove('cloudSyncEnabled');
    return out;
  }
}

class _ProfileAdapter implements SyncEntityAdapter {
  @override
  String get entity => 'profile';

  @override
  Future<bool> apply(DatabaseExecutor txn, SyncOp op, String myId) async {
    if (op.fields == null) return false;
    // LWW by timestamp stored under 'profile_ts'
    final rows = await txn.query('settings', where: 'key = ?', whereArgs: ['profile_ts'], limit: 1);
    int localTs = 0;
    if (rows.isNotEmpty) {
      localTs = int.tryParse(rows.first['value'] as String? ?? '0') ?? 0;
    }
    if (op.ts <= localTs) return false;
    final f = op.fields!;
    await txn.insert(
      'profile',
      {
        'id': 'me',
        'name': f['name'] ?? '',
        'email': f['email'] ?? '',
        'phone': f['phone'],
        'locale': f['locale'] ?? 'en-US',
        'timezone': f['timezone'] ?? 'UTC',
        'currency': f['currency'] ?? 'EUR',
        'country': f['country'] ?? 'US',
        'photo_path': null,
        'photo': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await txn.insert('settings', {'key': 'profile_ts', 'value': op.ts.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  @override
  Map<String, dynamic> toFields(Map<String, dynamic> source) {
    return {
      'name': (source['name'] ?? '').toString(),
      'email': (source['email'] ?? '').toString(),
      'phone': source['phone'],
      'locale': (source['locale'] ?? 'en-US').toString(),
      'timezone': (source['timezone'] ?? 'UTC').toString(),
      'currency': (source['currency'] ?? 'EUR').toString(),
      'country': (source['country'] ?? 'US').toString(),
    };
  }
}

bool _lwwAccept({
  required int incomingRev,
  required int incomingTs,
  required int localRev,
  required int localTs,
  required String myId,
  required String otherId,
}) {
  if (incomingRev > localRev) return true;
  if (incomingRev < localRev) return false;
  if (incomingTs > localTs) return true;
  if (incomingTs < localTs) return false;
  return otherId.compareTo(myId) > 0;
}
