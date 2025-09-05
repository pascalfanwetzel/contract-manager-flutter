import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// path_provider not needed; we use AppDirs
import '../fs/app_dirs.dart';

import 'key_service.dart';

/// Minimal device provisioning scaffold to enable automatic cross-device unlock
/// without prompting for a passphrase. This uses X25519 for key wrapping.
class ProvisioningService {
  ProvisioningService._();
  static final ProvisioningService instance = ProvisioningService._();

  static const _privKey = 'device_priv_x25519_v1';
  static const _pubKey = 'device_pub_x25519_v1';
  static const _devId = 'device_id_v1';
  final FlutterSecureStorage _ks = const FlutterSecureStorage();
  final X25519 _x = X25519();

  Future<String> deviceId() async {
    final existing = await _ks.read(key: _devId);
    if (existing != null) return existing;
    // Use random 32 bytes base64 as ID to avoid PII
    final r = Random.secure();
    final rnd = Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
    final id = base64UrlEncode(rnd);
    await _ks.write(key: _devId, value: id);
    return id;
  }

  Future<SimpleKeyPair> _getOrCreateKeyPair() async {
    final priv = await _ks.read(key: _privKey);
    final pub = await _ks.read(key: _pubKey);
    if (priv != null && pub != null) {
      final privBytes = base64Decode(priv);
      return _x.newKeyPairFromSeed(privBytes);
    }
    final kp = await _x.newKeyPair();
    final privBytes = await kp.extractPrivateKeyBytes();
    final pubKey = await kp.extractPublicKey();
    final pubBytes = pubKey.bytes;
    await _ks.write(key: _privKey, value: base64Encode(privBytes));
    await _ks.write(key: _pubKey, value: base64Encode(pubBytes));
    return kp;
  }

  Future<SimplePublicKey> publicKey() async {
    final kp = await _getOrCreateKeyPair();
    return await kp.extractPublicKey();
  }

  /// Wraps the current master key for the provided device public key.
  Future<Map<String, dynamic>> wrapMasterKeyFor({required SimplePublicKey receiverPublicKey}) async {
    final mk = await KeyService.instance.masterKey();
    final mkBytes = await mk.extractBytes();
    // Ephemeral sender keypair
    final eph = await _x.newKeyPair();
    final ephPub = await eph.extractPublicKey();
    // Derive shared secret
    final secret = await _x.sharedSecretKey(keyPair: eph, remotePublicKey: receiverPublicKey);
    // Derive wrap key via HKDF
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final wrapKey = await hkdf.deriveKey(secretKey: secret, info: utf8.encode('wrap:mk:v1'));
    final algo = AesGcm.with256bits();
    final nonce = algo.newNonce();
    final sb = await algo.encrypt(Uint8List.fromList(mkBytes), secretKey: wrapKey, nonce: nonce);
    return {
      'v': 1,
      'alg': 'x25519-aesgcm',
      'curve': 'X25519',
      'epk': base64Encode(ephPub.bytes),
      'nonce': base64Encode(sb.nonce),
      'ct': base64Encode(sb.cipherText),
      'mac': base64Encode(sb.mac.bytes),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Unwraps MK from a wrapped blob intended for this device.
  Future<Uint8List> unwrapMasterKey(Map<String, dynamic> wrapped) async {
    final kp = await _getOrCreateKeyPair();
    final priv = kp; // use for ECDH
    final epkBytes = base64Decode(wrapped['epk'] as String);
    final epk = SimplePublicKey(epkBytes, type: KeyPairType.x25519);
    final secret = await _x.sharedSecretKey(keyPair: priv, remotePublicKey: epk);
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final wrapKey = await hkdf.deriveKey(secretKey: secret, info: utf8.encode('wrap:mk:v1'));
    final algo = AesGcm.with256bits();
    final nonce = base64Decode(wrapped['nonce'] as String);
    final ct = base64Decode(wrapped['ct'] as String);
    final mac = Mac(base64Decode(wrapped['mac'] as String));
    final box = SecretBox(ct, nonce: nonce, mac: mac);
    final mkBytes = await algo.decrypt(box, secretKey: wrapKey);
    return Uint8List.fromList(mkBytes);
  }

  /// Attempts to auto-unlock by reading a locally stored wrapped MK.
  Future<bool> tryAutoUnlock() async {
    try {
      final dir = await AppDirs.supportDir();
      final devId = await deviceId();
      final file = File('${dir.path}/wrapped/$devId.mk');
      if (!await file.exists()) return false;
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mkBytes = await unwrapMasterKey(j);
      await KeyService.instance.setMasterKey(Uint8List.fromList(mkBytes));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Persists a wrapped MK blob for this device (used for local testing/provisioning).
  Future<void> saveWrappedForThisDevice(Map<String, dynamic> wrapped) async {
    final dir = await AppDirs.supportDir();
    final devId = await deviceId();
    final folder = Directory('${dir.path}/wrapped');
    if (!await folder.exists()) await folder.create(recursive: true);
    final f = File('${folder.path}/$devId.mk');
    await f.writeAsString(jsonEncode(wrapped), flush: true);
  }
}
