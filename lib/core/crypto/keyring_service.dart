import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../db/db_service.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show ConflictAlgorithm;

/// Manages the per-user Data Encryption Key (DEK) for cloud E2EE.
/// - DEK is stored locally inside the encrypted DB `settings` table (key: 'dek').
/// - Cloud holds only wrapped DEKs (passphrase/device), never plaintext.
class KeyringService {
  KeyringService._();
  static final KeyringService instance = KeyringService._();

  final _fs = FirebaseFirestore.instance;

  Future<Uint8List?> getLocalDek() async {
    final db = await DbService.instance.db;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['dek'], limit: 1);
    if (rows.isEmpty) return null;
    try {
      final b64 = rows.first['value'] as String;
      return Uint8List.fromList(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  Future<void> setLocalDek(Uint8List dek) async {
    final db = await DbService.instance.db;
    await db.insert('settings', {'key': 'dek', 'value': base64Encode(dek)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Uint8List> generateDek() async => Uint8List.fromList(List<int>.generate(32, (_) => Random.secure().nextInt(256)));

  // Passphrase wrap/unwrap using PBKDF2(HMAC-SHA256) and AES-GCM-256
  Future<Map<String, dynamic>> wrapDekWithPassphrase(Uint8List dek, String passphrase) async {
    final salt = _random(16);
    const iters = 200000; // strong default
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iters, bits: 256);
    final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    final keyBytes = await key.extractBytes();
    final algo = AesGcm.with256bits();
    final nonce = _random(12);
    final sb = await algo.encrypt(dek, secretKey: SecretKey(keyBytes), nonce: nonce);
    return {
      'v': 1,
      'type': 'pp',
      'alg': 'aes-gcm-256',
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': iters,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'wrapped': base64Encode(Uint8List.fromList([...sb.cipherText, ...sb.mac.bytes])),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<Uint8List> unwrapDekWithPassphrase(Map<String, dynamic> doc, String passphrase) async {
    final iters = (doc['iterations'] as num).toInt();
    final salt = base64Decode(doc['salt'] as String);
    final nonce = base64Decode(doc['nonce'] as String);
    final wrapped = base64Decode(doc['wrapped'] as String);
    final ct = wrapped.sublist(0, wrapped.length - 16);
    final mac = Mac(wrapped.sublist(wrapped.length - 16));
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iters, bits: 256);
    final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    final keyBytes = await key.extractBytes();
    final algo = AesGcm.with256bits();
    final dek = await algo.decrypt(SecretBox(ct, nonce: nonce, mac: mac), secretKey: SecretKey(keyBytes));
    return Uint8List.fromList(dek);
  }

  // Recovery code wrap (code is a high-entropy string we generate and show once)
  Future<String> generateRecoveryCode() async {
    final rand = Random.secure();
    final raw = Uint8List.fromList(List<int>.generate(32, (_) => rand.nextInt(256)));
    // Represent as hex with grouping: 8-4-4-4-12
    const hex = '0123456789abcdef';
    final sb = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      sb.write(hex[(raw[i] >> 4) & 0xF]);
      sb.write(hex[raw[i] & 0xF]);
    }
    final s = sb.toString();
    return '${s.substring(0,8)}-${s.substring(8,12)}-${s.substring(12,16)}-${s.substring(16,20)}-${s.substring(20,32)}';
  }

  Future<Map<String, dynamic>> wrapDekWithRecoveryCode(Uint8List dek, String recoveryCode) async {
    final salt = _random(16);
    const iters = 200000;
    final normalized = recoveryCode.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '');
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iters, bits: 256)
        .deriveKey(secretKey: SecretKey(utf8.encode('rc:$normalized')), nonce: salt);
    final keyBytes = await key.extractBytes();
    final algo = AesGcm.with256bits();
    final nonce = _random(12);
    final sb = await algo.encrypt(dek, secretKey: SecretKey(keyBytes), nonce: nonce);
    return {
      'v': 1,
      'type': 'rc',
      'alg': 'aes-gcm-256',
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': iters,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'wrapped': base64Encode(Uint8List.fromList([...sb.cipherText, ...sb.mac.bytes])),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<Uint8List> unwrapDekWithRecoveryCode(Map<String, dynamic> doc, String recoveryCode) async {
    final iters = (doc['iterations'] as num).toInt();
    final salt = base64Decode(doc['salt'] as String);
    final nonce = base64Decode(doc['nonce'] as String);
    final wrapped = base64Decode(doc['wrapped'] as String);
    final ct = wrapped.sublist(0, wrapped.length - 16);
    final mac = Mac(wrapped.sublist(wrapped.length - 16));
    final normalized = recoveryCode.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '');
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iters, bits: 256)
        .deriveKey(secretKey: SecretKey(utf8.encode('rc:$normalized')), nonce: salt);
    final keyBytes = await key.extractBytes();
    final algo = AesGcm.with256bits();
    final dek = await algo.decrypt(SecretBox(ct, nonce: nonce, mac: mac), secretKey: SecretKey(keyBytes));
    return Uint8List.fromList(dek);
  }

  Future<Map<String, dynamic>?> fetchRecoveryWrap(String uid, {bool throwOnError = false}) async {
    try {
      final doc = await _fs
          .collection('users')
          .doc(uid)
          .collection('keys')
          .doc('wrapped_dek_rc_v1')
          .get(const GetOptions(source: Source.server));
      if (!doc.exists) return null;
      return doc.data();
    } catch (e) {
      debugPrint('[Keyring] fetch recovery wrap failed: $e');
      if (throwOnError) rethrow;
      return null;
    }
  }

  Future<void> uploadRecoveryWrap(String uid, Map<String, dynamic> payload) async {
    await _fs.collection('users').doc(uid).collection('keys').doc('wrapped_dek_rc_v1').set(payload, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> fetchPassphraseWrap(String uid, {bool throwOnError = false}) async {
    try {
      final doc = await _fs
          .collection('users')
          .doc(uid)
          .collection('keys')
          .doc('wrapped_dek_pp_v1')
          .get(const GetOptions(source: Source.server));
      if (!doc.exists) return null;
      return doc.data();
    } catch (e) {
      debugPrint('[Keyring] fetch wrap failed: $e');
      if (throwOnError) rethrow;
      return null;
    }
  }

  Future<void> uploadPassphraseWrap(String uid, Map<String, dynamic> payload) async {
    await _fs.collection('users').doc(uid).collection('keys').doc('wrapped_dek_pp_v1').set(payload, SetOptions(merge: true));
  }

  Uint8List _random(int n) {
    final rand = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rand.nextInt(256)));
  }
}
