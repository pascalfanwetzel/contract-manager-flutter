import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AttachmentCryptoService {
  static const _keyName = 'attachments_aes_key_v1';
  static final _algo = AesGcm.with256bits();
  final FlutterSecureStorage _ks = const FlutterSecureStorage();

  Future<SecretKey> _getOrCreateKey() async {
    final existing = await _ks.read(key: _keyName);
    if (existing != null) {
      return SecretKey(base64Decode(existing));
    }
    final rnd = _algo.newSecretKey();
    final key = await rnd;
    final raw = await key.extractBytes();
    await _ks.write(key: _keyName, value: base64Encode(raw));
    return key;
  }

  // Encrypts data: returns [nonce (12)] + [ciphertext] + [mac(16)]
  Future<Uint8List> encrypt(Uint8List data) async {
    final key = await _getOrCreateKey();
    final nonce = _algo.newNonce();
    final secretBox = await _algo.encrypt(data, secretKey: key, nonce: await nonce);
    final out = Uint8List(secretBox.nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length);
    out.setAll(0, secretBox.nonce);
    out.setAll(secretBox.nonce.length, secretBox.cipherText);
    out.setAll(secretBox.nonce.length + secretBox.cipherText.length, secretBox.mac.bytes);
    return out;
  }

  Future<Uint8List> decrypt(Uint8List sealed) async {
    // Split into nonce(12) + cipher + mac(16)
    const nonceLen = 12;
    const macLen = 16;
    if (sealed.length < nonceLen + macLen) {
      throw ArgumentError('sealed data too short');
    }
    final nonce = sealed.sublist(0, nonceLen);
    final mac = Mac(sealed.sublist(sealed.length - macLen));
    final cipher = sealed.sublist(nonceLen, sealed.length - macLen);
    final key = await _getOrCreateKey();
    final box = SecretBox(cipher, nonce: nonce, mac: mac);
    final data = await _algo.decrypt(box, secretKey: key);
    return Uint8List.fromList(data);
  }
}

