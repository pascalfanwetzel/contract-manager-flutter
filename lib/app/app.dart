import 'dart:async';
import 'package:flutter/material.dart';
import 'router.dart';
import '../core/auth/auth_service.dart';
import '../core/cloud/provisioning_cloud_service.dart';
// removed unused passphrase/key service imports
import '../core/crypto/crypto_config.dart';
import '../core/notifications/notification_service.dart';
import '../core/db/db_service.dart';
import '../core/crypto/keyring_service.dart';
import '../core/cloud/snapshot_service.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'Contract Manager',
          themeMode: appState.themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          routerConfig: router,
          builder: (context, child) {
            final base = _AuthEffects(child: child ?? const SizedBox.shrink());
            if (!CryptoConfig.disableEncryption) return base;
            return _UnencryptedOverlay(child: base);
          },
        );
      },
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  const seed = Color(0xFFD5DEDD);
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  const radius = 12.0;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: scheme.surfaceTint,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      titleTextStyle: base.textTheme.titleMedium,
      subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: false,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      ),
      backgroundColor: scheme.surface,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: scheme.secondaryContainer,
      backgroundColor: scheme.surface,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorColor: scheme.primary,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      side: BorderSide(color: scheme.outlineVariant),
      selectedColor: scheme.secondaryContainer,
      labelStyle: base.textTheme.labelLarge,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
  );
}

// AppLockGate removed: biometric unlock is disabled for now.

class _AuthEffects extends StatefulWidget {
  final Widget child;
  const _AuthEffects({required this.child});
  @override
  State<_AuthEffects> createState() => _AuthEffectsState();
}

class _AuthEffectsState extends State<_AuthEffects> with WidgetsBindingObserver {
  StreamSubscription? _sub;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer notification permission prompt until after first frame to avoid
    // vendor UI churn warnings during initial layout.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try { await NotificationService.instance.requestPermissionIfNeeded(); } catch (_) {}
      // If DB failed to open/validate, prompt user to reset instead of auto-wiping silently
      if (appState.dbErrorMessage != null && mounted) {
        final msg = appState.dbErrorMessage!;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Local Database Locked'),
            content: Text('$msg\n\nYou can reset the local database to continue. This will delete local data on this device.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  // Close the dialog first, then perform async work to avoid using ctx after awaits
                  final nav = Navigator.of(ctx);
                  nav.pop();
                  try { await DbService.instance.resetAndReopen(); } catch (_) {}
                  if (!mounted) return;
                  appState.clearDbError();
                  await appState.rehydrateAll();
                },
                child: const Text('Reset now'),
              ),
            ],
          ),
        );
      }
    });
    _sub = AuthService.instance.userChanges.listen((u) async {
      if (u != null) {
        await AuthService.instance.prefillProfileIfEmpty(appState);
        if (appState.cloudSyncEnabled) {
          await ProvisioningCloudService.instance.onSignedIn();
        }
        if (!mounted) return;
        // Acquire context-bound helpers only after mounted check
        final messenger = ScaffoldMessenger.of(context);
        // Best-effort: update DEK availability flag; prompting handled in Privacy screen
        try {
          final dek = await KeyringService.instance.getLocalDek();
          appState.setCloudDekAvailable(dek != null);
        } catch (_) {
          appState.setCloudDekAvailable(false);
        }
        if (appState.isLocked && appState.cloudSyncEnabled) {
          final ok = await ProvisioningCloudService.instance.tryCloudAutoUnlock();
          if (ok && mounted) {
            await appState.unlockAfterExternalKeyInstall();
          }
        }
        // On fresh sign-in with cloud enabled and DEK present, await one initial sync
        if (appState.cloudSyncEnabled && appState.hasCloudDek) {
          appState.beginFreshCloudHydrate();
          try { await SnapshotService.instance.hydrateFromLatestSnapshotIfFresh(); } catch (_) {}
          try { await appState.syncNow(); } catch (_) {}
          try { await appState.rehydrateAll(); } catch (_) {}
        }
        
        // Toast about sync readiness
        if (!mounted) return;
        if (appState.cloudSyncEnabled) {
          if (appState.hasCloudDek) {
            messenger.showSnackBar(const SnackBar(content: Text('Cloud sync ready')));
          } else {
            messenger.showSnackBar(const SnackBar(content: Text('Finish cloud key setup to enable sync')));
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Ensure any pending DB writes are flushed when app is backgrounded.
      Future.microtask(() => appState.flushPendingSaves());
    } else if (state == AppLifecycleState.resumed && appState.cloudSyncEnabled) {
      // Fire-and-forget manual sync on foreground
      Future.microtask(() => appState.syncNow());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UnencryptedOverlay extends StatelessWidget {
  final Widget child;
  const _UnencryptedOverlay({required this.child});
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          child: _CornerBanner(message: 'ENCRYPTION DISABLED'),
        ),
      ],
    );
  }
}

class _CornerBanner extends StatelessWidget {
  final String message;
  const _CornerBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    // Compact diagonal banner similar to Flutter's Debug banner
    return ColoredBox(
      color: Colors.transparent,
      child: CustomPaint(
        painter: _BannerPainter(message: message, color: Colors.redAccent),
        child: const SizedBox(width: 120, height: 120),
      ),
    );
  }
}

class _BannerPainter extends CustomPainter {
  final String message;
  final Color color;
  _BannerPainter({required this.message, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..isAntiAlias = true;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);

    final tp = TextPainter(
      text: TextSpan(
        text: message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width * 0.9);

    canvas.save();
    canvas.translate(size.width * 0.22, size.height * 0.1);
    canvas.rotate(-0.785398); // -45 degrees in radians
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
