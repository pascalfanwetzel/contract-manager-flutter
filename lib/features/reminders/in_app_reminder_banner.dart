import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../contracts/data/app_state.dart';
import '../contracts/domain/models.dart';
import '../../app/routes.dart' as r;

class ReminderBannerHost extends StatefulWidget {
  final AppState state;
  final Widget child;
  const ReminderBannerHost({super.key, required this.state, required this.child});

  @override
  State<ReminderBannerHost> createState() => _ReminderBannerHostState();
}

class _ReminderBannerHostState extends State<ReminderBannerHost> with WidgetsBindingObserver {
  Timer? _timer;
  // Keep track of banners shown this calendar day to avoid repeats
  final Set<String> _shownToday = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_onStateChanged);
    // Initial check after first frame to ensure ScaffoldMessenger exists
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndMaybeShow());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkAndMaybeShow());
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _clearBanner();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndMaybeShow();
    }
  }

  void _onStateChanged() {
    // If toggles changed, update immediately
    _checkAndMaybeShow();
  }

  void _clearBanner() {
    if (!mounted) return;
    final sm = ScaffoldMessenger.maybeOf(context);
    sm?.clearMaterialBanners();
  }

  bool get _bannersEnabled => widget.state.remindersEnabled && widget.state.inAppBannerEnabled;

  void _checkAndMaybeShow() {
    if (!mounted) return;
    if (!_bannersEnabled) {
      _clearBanner();
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final timeOk = _timeOfDayReached(now, widget.state.reminderTime);

    // Reset daily memory when the day changes
    _shownToday.removeWhere((k) => !k.endsWith(_dayKey(today)));

    if (!timeOk) {
      // Before reminder time: clear any existing banner
      _clearBanner();
      return;
    }

    // Pick the next pending reminder for today
    final days = widget.state.reminderDays.toList()..sort();
    for (final c in widget.state.contracts) {
      if (!c.isActive || c.endDate == null) continue;
      for (final d in days) {
        final trigger = c.endDate!.subtract(Duration(days: d));
        final isToday = trigger.year == today.year && trigger.month == today.month && trigger.day == today.day;
        if (!isToday) continue;
        final key = '${c.id}|$d|${_dayKey(today)}';
        if (_shownToday.contains(key)) continue;
        _showBannerFor(c, d, key);
        return; // show one at a time
      }
    }
    // Nothing to show, clear any lingering banner
    _clearBanner();
  }

  bool _timeOfDayReached(DateTime now, TimeOfDay target) {
    final nowMinutes = now.hour * 60 + now.minute;
    final targetMinutes = target.hour * 60 + target.minute;
    return nowMinutes >= targetMinutes;
  }

  String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  void _showBannerFor(Contract c, int days, String key) {
    _shownToday.add(key);
    final cs = Theme.of(context).colorScheme;
    final end = c.endDate!;
    final dateStr = '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    final banner = MaterialBanner(
      backgroundColor: cs.secondaryContainer,
      leading: Icon(Icons.event_note, color: cs.onSecondaryContainer),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Upcoming contract end',
            style: TextStyle(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${c.title} ends in $days day${days == 1 ? '' : 's'} • $dateStr',
            style: TextStyle(color: cs.onSecondaryContainer),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _clearBanner();
            if (!mounted) return;
            context.go(r.AppRoutes.contractDetails(c.id));
          },
          child: const Text('View'),
        ),
        TextButton(
          onPressed: _clearBanner,
          child: const Text('Dismiss'),
        ),
      ],
    );
    final sm = ScaffoldMessenger.maybeOf(context);
    if (sm != null) {
      sm.clearMaterialBanners();
      sm.showMaterialBanner(banner);
    } else {
      // If no ScaffoldMessenger yet (e.g., during init), try after a frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final sm2 = ScaffoldMessenger.maybeOf(context);
        if (sm2 == null) return;
        sm2.clearMaterialBanners();
        sm2.showMaterialBanner(banner);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
