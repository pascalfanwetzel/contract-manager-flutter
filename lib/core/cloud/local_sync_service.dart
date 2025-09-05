import 'dart:async';
// no direct DB row shape manipulation here; adapters handle details
import '../db/db_service.dart';
import 'oplog_models.dart';
import 'sync_service.dart';
import 'sync_registry.dart';

class LocalSyncService implements SyncService {
  bool _paused = true;
  Timer? _timer;
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
      if (_paused) return;
      await syncOnce();
      try { _afterSync?.call(); } catch (_) {}
    });
  }

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

  @override
  Future<void> applyRemoteOps(List<SyncOp> ops) async {
    if (ops.isEmpty) return;
    final db = await DbService.instance.db;
    final myId = await DbService.instance.deviceId();
    // Sort ops by ts, then rev to apply in order
    ops.sort((a, b) {
      final c = a.ts.compareTo(b.ts);
      if (c != 0) return c;
      return a.rev.compareTo(b.rev);
    });
    int skipped = 0;
    await db.transaction((txn) async {
      for (final op in ops) {
        switch (op.entity) {
          case 'category':
          case 'settings':
          case 'profile':
            final adapter = SyncRegistry.instance.adapterFor(op.entity);
            if (adapter != null) {
              skipped += await adapter.apply(txn, op, myId) ? 0 : 1;
              break;
            }
            skipped += 1;
            break;
          case 'contract':
            final aC = SyncRegistry.instance.adapterFor('contract');
            if (aC != null) {
              skipped += await aC.apply(txn, op, myId) ? 0 : 1;
              break;
            }
            skipped += 1;
            break;
          case 'attachment':
            final aA = SyncRegistry.instance.adapterFor('attachment');
            if (aA != null) {
              skipped += await aA.apply(txn, op, myId) ? 0 : 1;
              break;
            }
            skipped += 1;
            break;
          case 'note':
            final aN = SyncRegistry.instance.adapterFor('note');
            if (aN != null) {
              skipped += await aN.apply(txn, op, myId) ? 0 : 1;
              break;
            }
            skipped += 1;
            break;
          default:
            break;
        }
      }
    });
    // Best-effort apply: do not fail the entire sync if some ops are
    // older (LWW) or undecryptable; they'll be effectively ignored.
    if (skipped > 0) {
      // Log for diagnostics without aborting sync
      // ignore: avoid_print
      print('[Sync] Skipped $skipped op(s) during apply (older/undecryptable/unknown)');
    }
  }

  @override
  Future<void> syncOnce() async {
    // Local-only stub: do nothing.
    // Important: Do NOT advance the cursor here. Only the real
    // FirebaseSyncService should move the cursor after a successful push
    // to avoid losing pending ops while not signed in.
    return;
  }

  @override
  void setOnAfterSync(void Function()? cb) {
    _afterSync = cb;
  }

  // All entity applications handled by SyncRegistry adapters
}

