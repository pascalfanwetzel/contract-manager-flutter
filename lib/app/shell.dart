import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/contracts/data/app_state.dart';
import '../features/reminders/in_app_reminder_banner.dart';
import 'routes.dart';

class HomeShell extends StatelessWidget {
  final AppState state;
  final Widget child; // current routed page
  const HomeShell({super.key, required this.state, required this.child});

    int _indexFromLocation(String loc) {
      if (loc.startsWith(AppRoutes.contracts)) return 1;
      if (loc.startsWith(AppRoutes.profile)) return 2;
      return 0; // overview default
    }

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    final idx = _indexFromLocation(loc);
      final paths = const [
        AppRoutes.overview,
        AppRoutes.contracts,
        AppRoutes.profile,
      ];

    return Scaffold(
      body: Stack(
        children: [
          ReminderBannerHost(
            state: state,
            child: SafeArea(child: child),
          ),
          // Auth overlay removed: we redirect to Welcome page instead
          if (state.isLocked) const _UnlockOverlay(),
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          return NavigationBar(
            selectedIndex: idx,
            onDestinationSelected: (i) => context.go(paths[i]),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Overview',
              ),
              const NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description),
                label: 'Contracts',
              ),
              NavigationDestination(
                icon: _profileTabIcon(state, selected: false),
                selectedIcon: _profileTabIcon(state, selected: true),
                label: 'Profile',
              ),
            ],
          );
        },
      ),
    );
  }
}

// Auth overlay removed; Welcome page handles sign-in UX.

Widget _profileTabIcon(AppState state, {required bool selected}) {
  final p = state.profile;
  final hasPhotoMem = p.photoBytes != null && p.photoBytes!.isNotEmpty;
  final hasPhotoFile = (p.photoPath != null && p.photoPath!.isNotEmpty && File(p.photoPath!).existsSync());
  final double radius = 12; // fits nicely in NavigationBar
  final ImageProvider? imgProvider = hasPhotoMem
      ? MemoryImage(Uint8List.fromList(p.photoBytes!))
      : (hasPhotoFile ? FileImage(File(p.photoPath!)) : null);

  final avatar = CircleAvatar(
    radius: radius,
    backgroundColor: selected ? Colors.blueGrey.shade100 : Colors.grey.shade300,
    backgroundImage: imgProvider,
    child: (hasPhotoMem || hasPhotoFile)
        ? null
        : (p.name.trim().isEmpty
            ? Icon(Icons.person, size: 16, color: Colors.grey.shade800)
            : Text(
                p.initials,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              )),
  );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: avatar,
  );
}

class _UnlockOverlay extends StatefulWidget {
  const _UnlockOverlay();
  @override
  State<_UnlockOverlay> createState() => _UnlockOverlayState();
}

class _UnlockOverlayState extends State<_UnlockOverlay> {
  final _ctl = TextEditingController();
  bool _obscured = true;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorWidgetOfExactType<HomeShell>()!.state;
    return Positioned.fill(
      child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Unlock Backup', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your encryption passphrase to unlock your data on this device.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ctl,
                      obscureText: _obscured,
                      decoration: InputDecoration(
                        labelText: 'Passphrase',
                        suffixIcon: IconButton(
                          icon: Icon(_obscured ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscured = !_obscured),
                        ),
                      ),
                      onSubmitted: (_) => _onUnlock(state),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : () => _onUnlock(state),
                      child: _busy ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Unlock'),
                    ),
                  ],
                ),
              ),
            ),
        ),
      ),
    );
  }

  Future<void> _onUnlock(AppState state) async {
    setState(() { _busy = true; _error = null; });
    final ok = await state.unlockWithPassphrase(_ctl.text.trim());
    if (!mounted) return;
    if (!ok) {
      setState(() { _busy = false; _error = 'Wrong passphrase. Try again.'; });
    } else {
      setState(() { _busy = false; _error = null; });
    }
  }
}
