import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../db/db_service.dart';
import '../crypto/keyring_service.dart';
import '../crypto/blob_crypto.dart';
import 'oplog_models.dart';
import 'sync_service.dart';
import 'local_sync_service.dart';

class FirebaseSyncService implements SyncService {
  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  bool _paused = true;
  Timer? _timer;
  int _backoffMs = 0; // basic exponential backoff on failures
  DateTime? _backoffUntil;
  void Function()? _afterSync;

  @override
  bool get isPaused => _paused;

  @override
  Future<void> start() async {
    _paused = false;
    _schedule();
  }

  @override
  Future<void> pause() async {
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        if (_paused) return;
        final user = _auth.currentUser;
        if (user == null) return; // not signed in
        await syncOnce();
      } catch (e, st) {
        debugPrint('[Sync] tick error: $e\n$st');
      }
    });
  }

  String _userOpsPath(String uid) => 'users/$uid/oplog';
  String _userBlobsPath(String uid) => 'users/$uid/blobs';
  String _userIdxPath(String uid) => 'users/$uid/attachments_index';

  @override
  Future<List<SyncOp>> pendingLocalOps({int limit = 200}) async {
    final since = await DbService.instance.getPushCursorTs();
    final rows = await DbService.instance.fetchOplogSince(since, limit: limit);
    return rows.map(SyncOp.fromRow).toList();
  }

  @override
  Future<void> markLocalPushedUpToTs(int ts) async {
    await DbService.instance.setPushCursorTs(ts);
  }

  Future<void> _pushLocalOps(String uid) async {
    final ops = await pendingLocalOps(limit: 200);
    if (ops.isEmpty) return;
    final batch = _firestore.batch();
    // Track attachment index updates separately so a permission issue on the
    // non-critical index does not abort the oplog batch commit.
    final Map<String, int> idxDelta = {}; // hash -> delta (+1/-1)
    final Map<String, int> idxTs = {}; // hash -> lastSeenTs (max)
    int maxTs = 0;
    for (final op in ops) {
      maxTs = op.ts > maxTs ? op.ts : maxTs;
      final docRef = _firestore.collection(_userOpsPath(uid)).doc(op.opId);
      Map<String, dynamic>? payload;
      if (op.fields != null) {
        try {
          final dek = await KeyringService.instance.getLocalDek();
          if (dek == null) throw StateError('Cloud DEK unavailable');
          final mkBytes = dek;
          final plain = Uint8List.fromList(utf8.encode(jsonEncode(op.fields)));
          final enc = await BlobCrypto.encrypt(plain, mkBytes);
          payload = {'payload_enc': base64Encode(enc)};
        } catch (e) {
          debugPrint('[Sync] payload encrypt failed: $e');
          payload = null;
        }
      }
      batch.set(docRef, {
        'op_id': op.opId,
        'entity': op.entity,
        'entity_id': op.entityId,
        'op': op.op,
        'rev': op.rev,
        'ts': op.ts,
        'device_id': op.deviceId,
        if (payload != null) ...payload,
      }, SetOptions(merge: true));
      if (op.entity == 'attachment' && op.op == 'put') {
        final hash = op.fields?['blob_hash'] as String?;
        if (hash != null && hash.isNotEmpty) {
          // Upload blob if not present
          final db = await DbService.instance.db;
          final ref = _storage.ref('${_userBlobsPath(uid)}/$hash');
          var exists = true;
          try { await ref.getMetadata(); } catch (_) { exists = false; }
          if (!exists) {
            final rows = await db.query('blobs', where: 'hash = ?', whereArgs: [hash], limit: 1);
            if (rows.isNotEmpty) {
              final data = rows.first['data'] as Uint8List;
              try {
                final dek = await KeyringService.instance.getLocalDek();
                if (dek == null) throw StateError('Cloud DEK unavailable');
                final enc = await BlobCrypto.encrypt(data, dek);
                await ref.putData(enc, SettableMetadata(contentType: 'application/octet-stream'));
              } catch (e) {
                debugPrint('[Sync] blob encrypt/upload failed for $hash: $e');
              }
            }
          }
          // Queue attachments_index update for post-commit, non-fatal write
          idxDelta.update(hash, (v) => v + 1, ifAbsent: () => 1);
          idxTs.update(hash, (v) => op.ts > v ? op.ts : v, ifAbsent: () => op.ts);
        }
      }
      if (op.entity == 'attachment' && op.op == 'delete') {
        final hash = op.fields?['blob_hash'] as String?;
        if (hash != null && hash.isNotEmpty) {
          idxDelta.update(hash, (v) => v - 1, ifAbsent: () => -1);
          idxTs.update(hash, (v) => op.ts > v ? op.ts : v, ifAbsent: () => op.ts);
        }
      }
    }
    await batch.commit();
    await markLocalPushedUpToTs(maxTs);
    // Best-effort: apply index updates. Failure here should not block sync.
    if (idxDelta.isNotEmpty) {
      for (final entry in idxDelta.entries) {
        final hash = entry.key;
        final delta = entry.value;
        final ts = idxTs[hash] ?? maxTs;
        try {
          final idxRef = _firestore.collection(_userIdxPath(uid)).doc(hash);
          await idxRef.set({
            'refcount': FieldValue.increment(delta),
            'lastSeenTs': ts,
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('[Sync] index update failed for $hash: $e');
        }
      }
    }
  }

  Future<void> _pullRemoteOps(String uid) async {
    var since = await DbService.instance.getPullCursorTs();
    const page = 200;
    while (true) {
      final q = await _firestore
          .collection(_userOpsPath(uid))
          .where('ts', isGreaterThan: since)
          .orderBy('ts')
          .limit(page)
          .get();
      if (q.docs.isEmpty) break;
      final ops = await Future.wait(q.docs.map((d) async {
        final j = d.data();
        Map<String, dynamic>? fields;
        // Prefer plaintext fields if present; otherwise decrypt payload_enc
        final rawFields = j['fields'];
        if (rawFields is Map<String, dynamic>) {
          fields = Map<String, dynamic>.from(rawFields);
        } else if (j['payload_enc'] != null) {
          try {
            final dek = await KeyringService.instance.getLocalDek();
            if (dek == null) throw StateError('Cloud DEK unavailable');
            final enc = base64Decode(j['payload_enc'] as String);
            final plain = await BlobCrypto.decrypt(enc, dek);
            fields = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
          } catch (e) {
            debugPrint('[Sync] payload decrypt failed for ${d.id}: $e');
            fields = null;
          }
        }
        return SyncOp(
          opId: j['op_id'] as String? ?? d.id,
          entity: j['entity'] as String,
          entityId: j['entity_id'] as String,
          op: j['op'] as String,
          rev: (j['rev'] as num?)?.toInt() ?? 0,
          ts: (j['ts'] as num?)?.toInt() ?? 0,
          deviceId: j['device_id'] as String? ?? 'unknown',
          fields: fields,
        );
      }));
      // Ensure blobs exist locally for attachment puts before applying
      await _prefetchMissingBlobs(uid, ops);
      // Apply with LWW rules using local service logic
      final local = LocalSyncService();
      await local.applyRemoteOps(ops);
      since = ops.fold<int>(since, (m, e) => e.ts > m ? e.ts : m);
      await DbService.instance.setPullCursorTs(since);
      if (q.docs.length < page) break; // caught up
    }
  }

  @override
  Future<void> applyRemoteOps(List<SyncOp> ops) async {
    // Not used directly; pullRemoteOps applies via LocalSyncService.
    final local = LocalSyncService();
    await local.applyRemoteOps(ops);
  }

  @override
  Future<void> syncOnce() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    if (_backoffUntil != null && now.isBefore(_backoffUntil!)) {
      return; // respect backoff window
    }
    try {
      await _pushLocalOps(user.uid);
      await _pullRemoteOps(user.uid);
      _backoffMs = 0; // reset on success
      _backoffUntil = null;
      // Notify after a successful cycle
      try { _afterSync?.call(); } catch (_) {}
    } catch (e) {
      // simple exponential backoff up to 5 minutes
      _backoffMs = _backoffMs == 0 ? 2000 : (_backoffMs * 2).clamp(2000, 300000);
      _backoffUntil = DateTime.now().add(Duration(milliseconds: _backoffMs));
      rethrow;
    }
  }

  @override
  void setOnAfterSync(void Function()? cb) {
    _afterSync = cb;
  }

  Future<void> _prefetchMissingBlobs(String uid, List<SyncOp> ops) async {
    final puts = ops.where((o) => o.entity == 'attachment' && o.op == 'put');
    if (puts.isEmpty) return;
    final db = await DbService.instance.db;
    const maxDownload = 25 * 1024 * 1024; // 25 MB safety cap
    for (final op in puts) {
      final hash = op.fields?['blob_hash'] as String?;
      if (hash == null || hash.isEmpty) continue;
      final existing = await db.query('blobs', where: 'hash = ?', whereArgs: [hash], limit: 1);
      if (existing.isNotEmpty) continue;
      try {
        final ref = _storage.ref('${_userBlobsPath(uid)}/$hash');
        final data = await ref.getData(maxDownload);
        if (data != null) {
          try {
            final dek = await KeyringService.instance.getLocalDek();
            if (dek == null) throw StateError('Cloud DEK unavailable');
            final plain = await BlobCrypto.decrypt(data, dek);
            await db.insert('blobs', {'hash': hash, 'data': plain, 'refcount': 1});
          } catch (e) {
            debugPrint('[Sync] blob decrypt failed for $hash: $e');
          }
        }
      } catch (_) {
        // ignore download errors for now; apply op anyway (attachment bytes may be fetched later on demand)
      }
    }
  }
}
