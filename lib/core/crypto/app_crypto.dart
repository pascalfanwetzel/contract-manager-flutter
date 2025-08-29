import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'key_service.dart';

/// App-wide crypto utilities backed by a device-bound master key.
class AppCrypto {
  static final AesGcm _algo = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<SecretKey> _domainKey(String domain) async {
    final mk = await KeyService.instance.masterKey();
    // Derive a stable per-domain key from master key using HKDF.
    final dk = await _hkdf.deriveKey(
      secretKey: mk,
      info: utf8.encode('ord_project:$domain:v1'),
      // No salt required for HKDF when IKM is high-entropy; keep null.
    );
    return dk;
  }

  /// Encrypts bytes with a domain-specific key: returns [nonce(12)] + [cipher] + [mac(16)]
  static Future<Uint8List> encryptBytes(Uint8List bytes, {required String domain}) async {
    final key = await _domainKey(domain);
    final nonce = _algo.newNonce();
    final sb = await _algo.encrypt(bytes, secretKey: key, nonce: nonce);
    final out = Uint8List(sb.nonce.length + sb.cipherText.length + sb.mac.bytes.length);
    out.setAll(0, sb.nonce);
    out.setAll(sb.nonce.length, sb.cipherText);
    out.setAll(sb.nonce.length + sb.cipherText.length, sb.mac.bytes);
    return out;
  }

  static Future<Uint8List> decryptBytes(Uint8List sealed, {required String domain}) async {
    const nonceLen = 12;
    const macLen = 16;
    if (sealed.length < nonceLen + macLen) {
      throw ArgumentError('sealed data too short');
    }
    final nonce = sealed.sublist(0, nonceLen);
    final mac = Mac(sealed.sublist(sealed.length - macLen));
    final cipher = sealed.sublist(nonceLen, sealed.length - macLen);
    final key = await _domainKey(domain);
    final box = SecretBox(cipher, nonce: nonce, mac: mac);
    final data = await _algo.decrypt(box, secretKey: key);
    return Uint8List.fromList(data);
  }
}
