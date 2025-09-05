import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class BlobCrypto {
  static const _version = 1;

  static Future<Uint8List> encrypt(Uint8List plaintext, Uint8List masterKeyBytes) async {
    final rng = _Rng();
    final salt = rng.bytes(16);
    final nonce = rng.bytes(12);
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(masterKeyBytes),
      info: utf8.encode('ord_project:blob'),
      nonce: salt,
    );
    final keyBytes = await derived.extractBytes();
    final algo = AesGcm.with256bits();
    final sb = await algo.encrypt(plaintext, secretKey: SecretKey(keyBytes), nonce: nonce);
    final header = {
      'v': _version,
      'alg': 'aes-gcm-256',
      'kdf': 'hkdf-sha256',
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
    };
    final headerBytes = utf8.encode(jsonEncode(header));
    final len = ByteData(4)..setUint32(0, headerBytes.length, Endian.big);
    return Uint8List.fromList([
      ...len.buffer.asUint8List(),
      ...headerBytes,
      ...sb.cipherText,
      ...sb.mac.bytes,
    ]);
  }

  static Future<Uint8List> decrypt(Uint8List cipher, Uint8List masterKeyBytes) async {
    if (cipher.length < 4) {
      throw const FormatException('cipher too short');
    }
    final hlen = ByteData.sublistView(cipher, 0, 4).getUint32(0, Endian.big);
    final headerJson = utf8.decode(cipher.sublist(4, 4 + hlen));
    final header = jsonDecode(headerJson) as Map<String, dynamic>;
    final hv = (header['v'] as num?)?.toInt() ?? 0;
    if (hv != _version) throw const FormatException('unsupported blob header');
    final salt = base64Decode(header['salt'] as String);
    final nonce = base64Decode(header['nonce'] as String);
    final ct = cipher.sublist(4 + hlen, cipher.length - 16);
    final mac = Mac(cipher.sublist(cipher.length - 16));
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(masterKeyBytes),
      info: utf8.encode('ord_project:blob'),
      nonce: salt,
    );
    final keyBytes = await derived.extractBytes();
    final algo = AesGcm.with256bits();
    final out = await algo.decrypt(SecretBox(ct, nonce: nonce, mac: mac), secretKey: SecretKey(keyBytes));
    return Uint8List.fromList(out);
  }
}

class _Rng {
  final _rand = Random.secure();
  Uint8List bytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rand.nextInt(256)));
}
