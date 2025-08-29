import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provides a device-bound master key (MK) for encrypting local data.
///
/// Phase 1: MK is generated on first use and stored in the OS keystore via
/// flutter_secure_storage. Passphrase wrapping is used for export/import only.
class KeyService {
  KeyService._();
  static final KeyService instance = KeyService._();

  static const _mkKey = 'master_key_v1';
  final FlutterSecureStorage _ks = const FlutterSecureStorage();

  Future<Uint8List> _getOrCreateMasterKeyBytes() async {
    final existing = await _ks.read(key: _mkKey);
    if (existing != null) {
      return Uint8List.fromList(base64Decode(existing));
    }
    // Generate 32 random bytes (CSPRNG)
    final r = Random.secure();
    final key = Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
    await _ks.write(key: _mkKey, value: base64Encode(key));
    return key;
    }

  Future<SecretKey> masterKey() async {
    final raw = await _getOrCreateMasterKeyBytes();
    return SecretKey(raw);
  }

  Future<void> setMasterKey(Uint8List bytes) async {
    await _ks.write(key: _mkKey, value: base64Encode(bytes));
  }

  Future<bool> hasMasterKey() async {
    final existing = await _ks.read(key: _mkKey);
    return existing != null;
  }

  /// Danger: Removes the device-bound MK. Any existing encrypted files will
  /// become undecryptable. Intended for full wipe flows only.
  Future<void> wipeMasterKey() async {
    try { await _ks.delete(key: _mkKey); } catch (_) {}
  }
}
