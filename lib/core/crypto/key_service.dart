import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
// path_provider not needed; we use AppDirs
import '../fs/app_dirs.dart';
import 'crypto_config.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show getDatabasesPath; // for Android DB dir fallback

/// Provides a device-bound master key (MK) for encrypting local data.
///
/// Phase 1: MK is generated on first use and stored in the OS keystore via
/// flutter_secure_storage. Passphrase wrapping is used for export/import only.
class KeyService {
  KeyService._();
  static final KeyService instance = KeyService._();

  static const _mkKey = 'master_key_v1';
  final FlutterSecureStorage _ks = const FlutterSecureStorage();

  // Fallback storage for environments where secure storage is unavailable
  Future<File> _fallbackFile() async {
    final dir = await AppDirs.supportDir();
    return File('${dir.path}/mk.bin');
  }

  Future<File> _fallbackDbDirFile() async {
    try {
      final base = await getDatabasesPath();
      return File('$base/mk.bin');
    } catch (_) {
      return _fallbackFile();
    }
  }

  Future<Uint8List?> _readMasterKeyBytes() async {
    if (CryptoConfig.disableEncryption) {
      // When disabled, pretend MK exists (dummy bytes)
      return Uint8List(32);
    }
    try {
      final existing = await _ks.read(key: _mkKey);
      if (existing != null) {
        debugPrint('[MK] Read from secure storage');
        return Uint8List.fromList(base64Decode(existing));
      }
    } catch (_) {
      // Secure storage unavailable; try fallback
    }
    if (!kReleaseMode) {
      try {
        final f = await _fallbackFile();
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          if (bytes.isNotEmpty) {
            debugPrint('[MK] Read from support dir file ${f.path}');
            return Uint8List.fromList(bytes);
          }
        }
      } catch (_) {}
      try {
        final f2 = await _fallbackDbDirFile();
        if (await f2.exists()) {
          final bytes = await f2.readAsBytes();
          if (bytes.isNotEmpty) {
            debugPrint('[MK] Read from DB dir file ${f2.path}');
            return Uint8List.fromList(bytes);
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Ensures a master key exists for first-run scenarios with no encrypted data.
  /// Does nothing if a key already exists.
  Future<void> ensureInitialized() async {
    if (CryptoConfig.disableEncryption) {
      // No-op when encryption is disabled
      return;
    }
    try {
      final existing = await _ks.read(key: _mkKey);
      if (existing != null) return;
    } catch (_) {
      // fall through to file fallback
    }
    final r = Random.secure();
    final key = Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
    try {
      await _ks.write(key: _mkKey, value: base64Encode(key));
      debugPrint('[MK] Initialized and wrote to secure storage');
      if (!kReleaseMode) {
        // Also mirror to fallbacks as redundancy
        try { final f = await _fallbackFile(); await f.writeAsBytes(key, flush: true); debugPrint('[MK] Mirrored to ${f.path}'); } catch (_) {}
        try { final f2 = await _fallbackDbDirFile(); await f2.writeAsBytes(key, flush: true); debugPrint('[MK] Mirrored to ${f2.path}'); } catch (_) {}
      }
      return;
    } catch (_) {
      // Secure storage not available; use fallback file
      try {
        if (kReleaseMode) {
          rethrow;
        }
        final f = await _fallbackFile();
        await f.writeAsBytes(key, flush: true);
        debugPrint('[MK] Initialized in support dir file ${f.path}');
        try { final f2 = await _fallbackDbDirFile(); await f2.writeAsBytes(key, flush: true); debugPrint('[MK] Mirrored to ${f2.path}'); } catch (_) {}
      } catch (_) {
        // Rethrow a StateError to signal failure to callers
        throw StateError('Unable to initialize master key storage');
      }
    }
  }

  /// Returns the existing master key. Throws if not available.
  Future<SecretKey> masterKey() async {
    if (CryptoConfig.disableEncryption) {
      return SecretKey(Uint8List(32));
    }
    // Try to read; if missing, auto-initialize once to avoid "missing key" races.
    var raw = await _readMasterKeyBytes();
    if (raw == null) {
      try {
        await ensureInitialized();
        raw = await _readMasterKeyBytes();
      } catch (_) {
        // fall through to throw below if still null
      }
    }
    if (raw == null) {
      throw StateError('Master key not available. Unlock required.');
    }
    return SecretKey(raw);
  }

  Future<void> setMasterKey(Uint8List bytes) async {
    if (CryptoConfig.disableEncryption) {
      // No-op
      return;
    }
    try {
      await _ks.write(key: _mkKey, value: base64Encode(bytes));
      debugPrint('[MK] Stored to secure storage');
    } catch (_) {
      if (kReleaseMode) rethrow;
      // Fallback to file-based storage
      final f = await _fallbackFile();
      await f.writeAsBytes(bytes, flush: true);
      debugPrint('[MK] Stored to support dir file ${f.path}');
    }
    // Best-effort mirror
    if (!kReleaseMode) {
      try { final f2 = await _fallbackDbDirFile(); await f2.writeAsBytes(bytes, flush: true); debugPrint('[MK] Mirrored to ${f2.path}'); } catch (_) {}
    }
  }

  Future<bool> hasMasterKey() async {
    if (CryptoConfig.disableEncryption) {
      return true;
    }
    try {
      final existing = await _ks.read(key: _mkKey);
      if (existing != null) return true;
    } catch (_) {}
    try {
      final f = await _fallbackFile();
      return await f.exists();
    } catch (_) {
      return false;
    }
  }

  /// Danger: Removes the device-bound MK. Any existing encrypted files will
  /// become undecryptable. Intended for full wipe flows only.
  Future<void> wipeMasterKey() async {
    if (CryptoConfig.disableEncryption) return;
    try { await _ks.delete(key: _mkKey); } catch (_) {}
    try {
      final f = await _fallbackFile();
      if (await f.exists()) { await f.delete(); }
    } catch (_) {}
    try {
      final f2 = await _fallbackDbDirFile();
      if (await f2.exists()) { await f2.delete(); }
    } catch (_) {}
  }
}
