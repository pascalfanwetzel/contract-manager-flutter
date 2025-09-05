import 'oplog_models.dart';

abstract class SyncService {
  Future<void> start();
  Future<void> pause();
  Future<void> resume();
  bool get isPaused;
  Future<void> syncOnce();

  // Local outbound
  Future<List<SyncOp>> pendingLocalOps({int limit = 200});
  Future<void> markLocalPushedUpToTs(int ts);

  // Inbound (from remote)
  Future<void> applyRemoteOps(List<SyncOp> ops);

  // Optional callback invoked after a successful sync cycle.
  void setOnAfterSync(void Function()? cb);
}
