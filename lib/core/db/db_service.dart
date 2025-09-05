import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'db_key.dart';
import 'package:flutter/foundation.dart';
import '../crypto/key_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

class DbOpenError implements Exception {
  final String message;
  DbOpenError(this.message);
  @override
  String toString() => 'DbOpenError: $message';
}

class DbService {
  DbService._();
  static final DbService instance = DbService._();
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  /// Closes, deletes, and reopens the database file. Use to recover from
  /// SQLCipher key mismatches or corrupted files.
  Future<void> resetAndReopen() async {
    try {
      if (_db != null) {
        try { await _db!.close(); } catch (_) {}
        _db = null;
      }
      final baseDir = await getDatabasesPath();
      final path = p.join(baseDir, 'app_enc.db');
      debugPrint('[DB] Resetting database at $path');
      try { await deleteDatabase(path); } catch (_) {}
      // Also remove potential stray files to ensure a clean state
      try {
        for (final name in ['app_enc.db']) {
          try { await deleteDatabase(p.join(baseDir, name)); } catch (_) {}
        }
      } catch (_) {}
    } catch (_) {}
    _db = await _open();
  }

  /// Closes the current database connection without deleting the file.
  Future<void> close() async {
    if (_db != null) {
      try { await _db!.close(); } catch (_) {}
      _db = null;
    }
  }

  Future<Database> _open() async {
    Future<void> onCreate(Database db, int version) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS contract_groups (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          built_in INTEGER NOT NULL,
          order_index INTEGER NOT NULL DEFAULT 0,
          icon TEXT,
          rev INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL DEFAULT 0,
          deleted INTEGER NOT NULL DEFAULT 0
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS contracts (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          provider TEXT NOT NULL,
          customer_number TEXT,
          category_id TEXT NOT NULL,
          cost_amount REAL,
          cost_currency TEXT,
          billing_cycle TEXT,
          payment_method TEXT,
          payment_note TEXT,
          start_date INTEGER,
          end_date INTEGER,
          is_open_ended INTEGER NOT NULL,
          is_active INTEGER NOT NULL,
          is_deleted INTEGER NOT NULL,
          notes TEXT,
          deleted_at INTEGER,
          rev INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL DEFAULT 0
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS notes (
          contract_id TEXT PRIMARY KEY,
          text TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS attachments (
          id TEXT PRIMARY KEY,
          contract_id TEXT NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          data BLOB NOT NULL,
          blob_hash TEXT,
          rev INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL DEFAULT 0,
          deleted INTEGER NOT NULL DEFAULT 0
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS thumbs (
          attachment_id TEXT NOT NULL,
          width INTEGER NOT NULL,
          data BLOB NOT NULL,
          PRIMARY KEY (attachment_id, width)
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS blobs (
          hash TEXT PRIMARY KEY,
          data BLOB NOT NULL,
          refcount INTEGER NOT NULL
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS profile (
          id TEXT PRIMARY KEY,
          name TEXT,
          email TEXT,
          phone TEXT,
          locale TEXT,
          timezone TEXT,
          currency TEXT,
          country TEXT,
          photo_path TEXT,
          photo BLOB
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS oplog (
          op_id TEXT PRIMARY KEY,
          entity TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          op TEXT NOT NULL,
          rev INTEGER NOT NULL,
          ts INTEGER NOT NULL,
          device_id TEXT NOT NULL,
          fields TEXT
        );
      ''');
      await db.insert('profile', {'id': 'me'}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Unencrypted mode removed: always open encrypted DB

    // Mobile (and macOS): use SQLCipher with password
    final base = await getDatabasesPath();
    final path = p.join(base, 'app_enc.db');
    // Removed unused pre-open existence check
    // Ensure MK is ready before deriving DB passphrase
    try { await KeyService.instance.ensureInitialized(); } catch (_) {}
    final hasMk = await KeyService.instance.hasMasterKey();
    final key = await DbKeyService.instance.get();
    debugPrint('[DB] Opening at $path (hasMk=$hasMk keyLen=${key.length})');
    Future<Database> openFresh() async => await openDatabase(
          path,
          password: key,
          version: 4,
          onOpen: (db) async {
            // Do not run PRAGMA cipher_migrate; it can fail on some devices.
            try { await db.execute('PRAGMA foreign_keys = ON;'); } catch (_) {}
            debugPrint('[DB] Opened successfully');
          },
          onCreate: (db, version) async => onCreate(db, version),
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 3) {
              // Safe ALTERs (ignore failures if columns already exist)
              Future<void> tryExec(String sql) async { try { await db.execute(sql); } catch (_) {} }
              await tryExec('ALTER TABLE contract_groups ADD COLUMN rev INTEGER NOT NULL DEFAULT 0');
              await tryExec('ALTER TABLE contract_groups ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
              await tryExec('ALTER TABLE contract_groups ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0');
              await tryExec('ALTER TABLE contracts ADD COLUMN rev INTEGER NOT NULL DEFAULT 0');
              await tryExec('ALTER TABLE contracts ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
              await tryExec('ALTER TABLE contracts ADD COLUMN deleted_at INTEGER');
              await tryExec('ALTER TABLE attachments ADD COLUMN blob_hash TEXT');
              await tryExec('ALTER TABLE attachments ADD COLUMN rev INTEGER NOT NULL DEFAULT 0');
              await tryExec('ALTER TABLE attachments ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
              await tryExec('ALTER TABLE attachments ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0');
              await tryExec('ALTER TABLE attachments ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0');
              await tryExec('CREATE TABLE IF NOT EXISTS blobs (hash TEXT PRIMARY KEY, data BLOB NOT NULL, refcount INTEGER NOT NULL)');
              await tryExec('CREATE TABLE IF NOT EXISTS oplog (op_id TEXT PRIMARY KEY, entity TEXT NOT NULL, entity_id TEXT NOT NULL, op TEXT NOT NULL, rev INTEGER NOT NULL, ts INTEGER NOT NULL, device_id TEXT NOT NULL, fields TEXT)');
              await tryExec('CREATE TABLE IF NOT EXISTS profile (id TEXT PRIMARY KEY, name TEXT, email TEXT, phone TEXT, locale TEXT, timezone TEXT, currency TEXT, country TEXT, photo_path TEXT, photo BLOB)');
              await tryExec('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
              // Seed profile row if missing
              try { await db.insert('profile', {'id': 'me'}); } catch (_) {}
            }
            if (oldVersion < 4) {
              // Add ordering + icon for categories
              Future<void> tryExec(String sql) async { try { await db.execute(sql); } catch (_) {} }
              await tryExec('ALTER TABLE contract_groups ADD COLUMN order_index INTEGER NOT NULL DEFAULT 0');
              await tryExec('ALTER TABLE contract_groups ADD COLUMN icon TEXT');
            }
          },
        );

    // Attempt to open the DB; if it looks invalid (wrong key/plaintext), recreate it once.
    Database db;
    try {
      db = await openFresh();
    } catch (e) {
      debugPrint('[DB] Open failed: $e');
      throw DbOpenError('Unable to open encrypted database. Wrong key or corrupt file.');
    }

    try {
      await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' LIMIT 1");
      return db;
    } catch (e) {
      debugPrint('[DB] Invalid DB (wrong key/plaintext): $e');
      try { await db.close(); } catch (_) {}
      throw DbOpenError('Encrypted database could not be validated. Likely wrong key.');
    }
  }

  // --- Device + Lamport timestamp helpers ---
  Future<String> deviceId() async {
    final db = await this.db;
    return deviceIdTx(db);
  }

  Future<String> deviceIdTx(DatabaseExecutor txn) async {
    final rows = await txn.query('settings', where: 'key = ?', whereArgs: ['device_id'], limit: 1);
    if (rows.isNotEmpty) return rows.first['value'] as String;
    final id = const Uuid().v4();
    await txn.insert('settings', {'key': 'device_id', 'value': id}, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<int> nextLamportTs([int? observedMs]) async {
    final db = await this.db;
    return nextLamportTsTx(db, observedMs);
  }

  Future<int> nextLamportTsTx(DatabaseExecutor txn, [int? observedMs]) async {
    int nowMs = DateTime.now().millisecondsSinceEpoch;
    int seen = nowMs;
    final rows = await txn.query('settings', where: 'key = ?', whereArgs: ['lamport_ts'], limit: 1);
    if (rows.isNotEmpty) {
      seen = int.tryParse(rows.first['value'] as String? ?? '') ?? nowMs;
    }
    final maxSeen = [seen, nowMs, observedMs ?? 0].reduce((a, b) => a > b ? a : b);
    final next = maxSeen + 1;
    await txn.insert('settings', {'key': 'lamport_ts', 'value': next.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
    return next;
  }

  Future<void> logOp({required String entity, required String entityId, required String op, required int rev, required int ts, Map<String, Object?>? fields}) async {
    final db = await this.db;
    await logOpTx(db, entity: entity, entityId: entityId, op: op, rev: rev, ts: ts, fields: fields);
  }

  Future<void> logOpTx(DatabaseExecutor txn, {required String entity, required String entityId, required String op, required int rev, required int ts, Map<String, Object?>? fields}) async {
    final opId = const Uuid().v4();
    final dev = await deviceIdTx(txn);
    await txn.insert('oplog', {
      'op_id': opId,
      'entity': entity,
      'entity_id': entityId,
      'op': op,
      'rev': rev,
      'ts': ts,
      'device_id': dev,
      'fields': fields == null ? null : jsonEncode(fields),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Allow access to nullable db without opening (for deviceId helper use-case)
  Future<Database?> dbOrNull() async => _db;

  // --- Oplog cursor helpers (for sync) ---
  // Separate cursors for outbound (push) and inbound (pull) to avoid skipping
  // remote ops when local clock/Lamport ts advances.
  Future<int> getPushCursorTs() async {
    final db = await this.db;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['push_cursor_ts'], limit: 1);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String? ?? '0') ?? 0;
  }

  Future<void> setPushCursorTs(int ts) async {
    final db = await this.db;
    await db.insert('settings', {'key': 'push_cursor_ts', 'value': ts.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> getPullCursorTs() async {
    final db = await this.db;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['pull_cursor_ts'], limit: 1);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String? ?? '0') ?? 0;
  }

  Future<void> setPullCursorTs(int ts) async {
    final db = await this.db;
    await db.insert('settings', {'key': 'pull_cursor_ts', 'value': ts.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> fetchOplogSince(int sinceTs, {int limit = 200}) async {
    final db = await this.db;
    return db.query(
      'oplog',
      where: 'ts > ?',
      whereArgs: [sinceTs],
      orderBy: 'ts ASC, rev ASC, device_id ASC',
      limit: limit,
    );
  }
}
