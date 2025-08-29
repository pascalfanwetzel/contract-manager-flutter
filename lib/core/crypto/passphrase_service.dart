import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import 'key_service.dart';

class PassphraseService {
  static const _fileName = 'emk.json';
  static const _iterations = 310000; // PBKDF2-HMAC-SHA256 strong cost

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<bool> hasPassphrase() async {
    final f = await _file();
    return f.exists();
  }

  static Future<void> clearPassphrase() async {
    final f = await _file();
    try { if (await f.exists()) await f.delete(); } catch (_) {}
  }

  static Future<void> setPassphrase(String passphrase) async {
    final mk = await KeyService.instance.masterKey();
    final mkBytes = await mk.extractBytes();

    // Derive SRK from passphrase with random salt
    final salt = await _randomBytes(16);
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256);
    final srk = await pbkdf2.deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    final srkBytes = await srk.extractBytes();

    // Encrypt MK with AES-GCM using SRK
    final algo = AesGcm.with256bits();
    final nonce = algo.newNonce();
    final sb = await algo.encrypt(Uint8List.fromList(mkBytes), secretKey: SecretKey(srkBytes), nonce: nonce);

    final json = jsonEncode({
      'v': 1,
      'kdf': 'pbkdf2-hmac-sha256',
      'iter': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(sb.nonce),
      'ct': base64Encode(sb.cipherText),
      'mac': base64Encode(sb.mac.bytes),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    final f = await _file();
    await f.writeAsString(json, flush: true);
  }

  /// Unlock using passphrase and write the MK into secure storage on this device.
  static Future<bool> unlockAndStore(String passphrase) async {
    final f = await _file();
    if (!await f.exists()) return false;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final iterations = (j['iter'] as int?) ?? _iterations;
      final salt = base64Decode(j['salt'] as String);
      final nonce = base64Decode(j['nonce'] as String);
      final ct = base64Decode(j['ct'] as String);
      final mac = Mac(base64Decode(j['mac'] as String));
      final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
      final srk = await pbkdf2.deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
      final srkBytes = await srk.extractBytes();
      final algo = AesGcm.with256bits();
      final box = SecretBox(ct, nonce: nonce, mac: mac);
      final mkBytes = await algo.decrypt(box, secretKey: SecretKey(srkBytes));
      // Store the recovered MK into secure storage
      await KeyService.instance.setMasterKey(Uint8List.fromList(mkBytes));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the timestamp when the passphrase-protected EMK was last written.
  /// Reads `createdAt` (ms since epoch) from the stored `emk.json` if present.
  static Future<DateTime?> passphraseSetAt() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final ts = j['createdAt'] as int?;
      if (ts == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> _randomBytes(int n) async {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }
}
