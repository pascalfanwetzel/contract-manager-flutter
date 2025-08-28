import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/contracts/domain/models.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(initSettings);

    // Android 13+ runtime permission
    if (Platform.isAndroid) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await androidImpl?.areNotificationsEnabled();
      if (enabled == false) {
        await androidImpl?.requestNotificationsPermission();
      }
    }

    // Timezone setup
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local));
    } catch (_) {
      // Fallback to UTC
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    _initialized = true;
  }

  Future<void> cancelForContract(String contractId) async {
    for (final days in const [1, 7, 14, 30]) {
      await _plugin.cancel(_idFor(contractId, days));
    }
  }

  Future<void> scheduleForContract({
    required Contract contract,
    required Set<int> days,
    required tz.TZDateTime Function(DateTime endDate) timeForEndDate,
  }) async {
    if (contract.endDate == null) return;
    final end = contract.endDate!;
    for (final d in days) {
      final when = timeForEndDate(end.subtract(Duration(days: d)));
      if (when.isBefore(tz.TZDateTime.now(tz.local))) continue;
      final id = _idFor(contract.id, d);
      await _plugin.zonedSchedule(
        id,
        'Contract reminder',
        '${contract.title} ends in $d day${d == 1 ? '' : 's'}',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'contract_reminders',
            'Contract Reminders',
            channelDescription: 'Reminders before contract expiration',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: contract.id,
      );
    }
  }

  int _idFor(String contractId, int days) => (contractId.hashCode ^ days.hashCode) & 0x7fffffff;
}
