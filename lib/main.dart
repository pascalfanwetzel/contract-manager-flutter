import 'package:flutter/material.dart';
import 'app/app.dart';
import 'core/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize local notifications before scheduling anything
  await NotificationService.instance.init();
  runApp(const App());
}
