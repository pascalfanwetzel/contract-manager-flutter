import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import '../db/db_service.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show ConflictAlgorithm;
import '../crypto/keyring_service.dart';
import '../crypto/blob_crypto.dart';

class SnapshotService {
  SnapshotService._();
  static final SnapshotService instance = SnapshotService._();

  static const int schemaVersion = 1;
  static const String _coll = 'snapshots';

  Future<bool> _hasLocalData() async {
    final db = await DbService.instance.db;
    final cats = await db.query('contract_groups', limit: 1);
    if (cats.isNotEmpty) return true;
    final cons = await db.query('contracts', limit: 1);
    return cons.isNotEmpty;
  }

  Future<bool> hydrateFromLatestSnapshotIfFresh() async {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    // Only apply on fresh/empty local datasets to avoid clobbering local changes
    final has = await _hasLocalData();
    if (has) return false;
    final qs = await FirebaseFirestore.instance
        .collection('users/${user.uid}/$_coll')
        .orderBy('ts', descending: true)
        .limit(1)
        .get();
    if (qs.docs.isEmpty) return false;
    final j = qs.docs.first.data();
    final int ts = (j['ts'] as num?)?.toInt() ?? 0;
    final String? encB64 = j['payload_enc'] as String?;
    if (encB64 == null || encB64.isEmpty) return false;
    try {
      final dek = await KeyringService.instance.getLocalDek();
      if (dek == null) throw StateError('Cloud DEK unavailable');
      final enc = base64Decode(encB64);
      final plain = await BlobCrypto.decrypt(enc, dek);
      final Map<String, dynamic> snap = jsonDecode(utf8.decode(plain));
      final int ver = (snap['schema'] as num?)?.toInt() ?? 0;
      if (ver != schemaVersion) return false; // ignore unknown versions for safety
      await _applySnapshotMap(snap, cursorTs: ts);
      // Set pull cursor to snapshot ts so initial pull only fetches delta
      await DbService.instance.setPullCursorTs(ts);
      return true;
    } catch (e, st) {
      debugPrint('[Snapshot] apply failed: $e\n$st');
      return false;
    }
  }

  Future<void> _applySnapshotMap(Map<String, dynamic> snap, {required int cursorTs}) async {
    final db = await DbService.instance.db;
    await db.transaction((txn) async {
      // Replace categories (non-deleted only in snapshot)
      await txn.delete('contract_groups');
      final cats = (snap['categories'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final c in cats) {
        await txn.insert('contract_groups', {
          'id': c['id'],
          'name': c['name'],
          'built_in': (c['built_in'] as bool? ?? false) ? 1 : 0,
          'order_index': (c['order_index'] as num?)?.toInt() ?? 0,
          'icon': c['icon'],
          'deleted': 0,
          'rev': (c['rev'] as num?)?.toInt() ?? 0,
          'updated_at': (c['updated_at'] as num?)?.toInt() ?? cursorTs,
        });
      }
      // Replace contracts (include deleted rows)
      await txn.delete('contracts');
      final cons = (snap['contracts'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final m in cons) {
        await txn.insert('contracts', Map<String, Object?>.from(m));
      }
      // Replace notes
      await txn.delete('notes');
      final notes = (snap['notes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final n in notes) {
        await txn.insert('notes', Map<String, Object?>.from(n));
      }
      // Profile (single row)
      final prof = (snap['profile'] as Map<String, dynamic>?);
      if (prof != null) {
        await txn.insert('profile', {
          'id': 'me',
          'name': prof['name'] ?? '',
          'email': prof['email'] ?? '',
          'phone': prof['phone'],
          'locale': prof['locale'] ?? 'en-US',
          'timezone': prof['timezone'] ?? 'UTC',
          'currency': prof['currency'] ?? 'EUR',
          'country': prof['country'] ?? 'US',
          'photo_path': null,
          'photo': null,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      // Settings
      final settings = (snap['settings'] as Map<String, dynamic>?);
      if (settings != null) {
        await txn.insert('settings', {
          'key': 'settings',
          'value': jsonEncode(settings),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert('settings', {'key': 'settings_ts', 'value': cursorTs.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> maybeWriteSnapshot({Duration minInterval = const Duration(hours: 24)}) async {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Throttle by time using a local marker in settings table
    final db = await DbService.instance.db;
    int lastMs = 0;
    final row = await db.query('settings', where: 'key = ?', whereArgs: ['snapshot_written_at_ms'], limit: 1);
    if (row.isNotEmpty) {
      lastMs = int.tryParse((row.first['value'] as String?) ?? '0') ?? 0;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - lastMs < minInterval.inMilliseconds) return;
    try {
      final payload = await _buildSnapshotMap();
      final dek = await KeyringService.instance.getLocalDek();
      if (dek == null) return;
      final bytes = utf8.encode(jsonEncode(payload));
      final enc = await BlobCrypto.encrypt(Uint8List.fromList(bytes), dek);
      final ts = (await DbService.instance.getPullCursorTs());
      await FirebaseFirestore.instance
          .collection('users/${user.uid}/$_coll')
          .doc('snap_$ts')
          .set({'ts': ts, 'schema': schemaVersion, 'payload_enc': base64Encode(enc)}, SetOptions(merge: true));
      await db.insert('settings', {'key': 'snapshot_written_at_ms', 'value': nowMs.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, st) {
      debugPrint('[Snapshot] write failed: $e\n$st');
    }
  }

  Future<Map<String, dynamic>> _buildSnapshotMap() async {
    final db = await DbService.instance.db;
    final catsRows = await db.query('contract_groups', where: 'deleted = 0', orderBy: 'order_index ASC, updated_at ASC');
    final consRows = await db.query('contracts');
    final notesRows = await db.query('notes');
    final profRows = await db.query('profile', where: 'id = ?', whereArgs: ['me'], limit: 1);
    final setRows = await db.query('settings', where: 'key = ?', whereArgs: ['settings'], limit: 1);
    Map<String, dynamic>? settings;
    if (setRows.isNotEmpty) {
      try { settings = jsonDecode(setRows.first['value'] as String) as Map<String, dynamic>; } catch (_) {}
    }
    return {
      'schema': schemaVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'categories': catsRows.map((r) => {
            'id': r['id'],
            'name': r['name'],
            'built_in': ((r['built_in'] as int?) ?? 0) == 1,
            'order_index': (r['order_index'] as int?) ?? 0,
            'icon': r['icon'],
            'rev': (r['rev'] as int?) ?? 0,
            'updated_at': (r['updated_at'] as int?) ?? 0,
          }).toList(),
      'contracts': consRows.map((r) => Map<String, Object?>.from(r)).toList(),
      'notes': notesRows.map((r) => Map<String, Object?>.from(r)).toList(),
      'profile': profRows.isNotEmpty
          ? {
              'name': profRows.first['name'],
              'email': profRows.first['email'],
              'phone': profRows.first['phone'],
              'locale': profRows.first['locale'],
              'timezone': profRows.first['timezone'],
              'currency': profRows.first['currency'],
              'country': profRows.first['country'],
            }
          : null,
      'settings': settings,
    };
  }
}
