import 'package:flutter/material.dart';
import 'app/app.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/notifications/notification_service.dart';
import 'core/crypto/crypto_config.dart';
import 'core/crypto/key_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize local notifications before scheduling anything
  await NotificationService.instance.init();
  // Ensure app master key is initialized before any encrypted DB open
  if (!CryptoConfig.disableEncryption) {
    try { await KeyService.instance.ensureInitialized(); } catch (_) {}
  }
  // Initialize Firebase (requires firebase_options.dart via flutterfire, or default)
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Allow app to run without Firebase during local dev if not configured
  }
  runApp(const App());
}
