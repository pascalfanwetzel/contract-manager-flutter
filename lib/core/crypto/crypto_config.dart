/// Global crypto configuration.
///
/// You can disable encryption via compile-time define:
///   flutter run --dart-define=DISABLE_ENCRYPTION=true
class CryptoConfig {
  /// When true, disables all encryption, decryption, passphrase, and MK usage.
  ///
  /// Read from a compile-time flag with a sane default.
  static bool disableEncryption = const bool.fromEnvironment(
    'DISABLE_ENCRYPTION',
    defaultValue: false,
  );
}
