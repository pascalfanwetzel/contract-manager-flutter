import 'package:flutter/material.dart';
import 'app/app.dart';
import 'core/notifications/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize local notifications
  NotificationService.instance.init();
  runApp(const App());
}
