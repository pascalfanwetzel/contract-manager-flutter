import 'dart:convert';
import '../crypto/key_service.dart';
import '../crypto/crypto_config.dart';

class DbKeyService {
  DbKeyService._();
  static final DbKeyService instance = DbKeyService._();

  // Derive SQLCipher passphrase directly from the master key; never persist a separate DB key.
  Future<String> get() async {
    if (CryptoConfig.disableEncryption) return 'disabled';
    final mk = await KeyService.instance.masterKey();
    final mkBytes = await mk.extractBytes();
    return base64Encode(mkBytes); // SQLCipher derives internal key from passphrase
  }
}
