import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:go_router/go_router.dart';
import '../../app/routes.dart' as r;
import '../../core/crypto/keyring_service.dart';
import '../contracts/data/app_state.dart';
import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;
import '../../core/cloud/snapshot_service.dart';

class UnlockPage extends StatefulWidget {
  final AppState state;
  const UnlockPage({super.key, required this.state});

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  bool _loading = true;
  bool _hasWrap = false;
  bool _netError = false;
  bool _obscure = true;
  bool _unlocking = false;
  String? _error;
  final _ctl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkRemoteKey();
  }

  Future<void> _checkRemoteKey() async {
    setState(() { _loading = true; _error = null; _netError = false; });
    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        context.go(r.AppRoutes.welcome);
        return;
      }
      // If local DEK exists, proceed offline and kick an immediate sync
      final localDek = await KeyringService.instance.getLocalDek();
      if (localDek != null) {
        widget.state.setCloudDekAvailable(true);
        // Try snapshot hydrate first on fresh installs; then delta sync
        widget.state.beginFreshCloudHydrate();
        try { await SnapshotService.instance.hydrateFromLatestSnapshotIfFresh(); } catch (_) {}
        try { await widget.state.syncNow(); } catch (_) {}
        try { await widget.state.rehydrateAll(); } catch (_) {}
        if (!mounted) return;
        context.go(r.AppRoutes.overview);
        return;
      }
      // No local DEK: verify existence of remote wrap from server (do not fall back to cache)
      final wrap = await KeyringService.instance
          .fetchPassphraseWrap(user.uid, throwOnError: true)
          .timeout(const Duration(seconds: 15));
      setState(() { _hasWrap = wrap != null; _netError = false; });
    } on TimeoutException catch (_) {
      setState(() { _hasWrap = false; _netError = true; _error = 'Unable to reach server. Check your connection and try again.'; });
    } catch (_) {
      setState(() { _hasWrap = false; _netError = true; _error = 'Unable to verify cloud key. Check your connection and try again.'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _onUnlock() async {
    final pass = _ctl.text.trim();
    if (pass.isEmpty) {
      setState(() { _error = 'Enter your passphrase'; });
      return;
    }
    setState(() { _unlocking = true; _error = null; });
    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() { _error = 'Session expired. Please sign in again.'; });
        return;
      }
      final wrap = await KeyringService.instance
          .fetchPassphraseWrap(user.uid, throwOnError: true)
          .timeout(const Duration(seconds: 15));
      if (wrap == null) {
        setState(() { _error = 'No cloud key found for this account. If this is unexpected, contact support.'; });
        return;
      }
      try {
        final dek = await KeyringService.instance.unwrapDekWithPassphrase(wrap, pass);
        await KeyringService.instance.setLocalDek(dek);
      } on SecretBoxAuthenticationError {
        setState(() { _error = 'Wrong passphrase. Try again.'; });
        return;
      } catch (e) {
        setState(() { _error = 'Unable to unlock: $e'; });
        return;
      }
      widget.state.setCloudDekAvailable(true);
      // Turn on cloud sync, clear stale view, and try an immediate sync
      widget.state.setCloudSyncEnabled(true);
      widget.state.beginFreshCloudHydrate();
      try { await SnapshotService.instance.hydrateFromLatestSnapshotIfFresh(); } catch (_) {}
      String? syncErr;
      try {
        await widget.state.syncNow();
        await widget.state.rehydrateAll();
        syncErr = widget.state.lastSyncError;
      } catch (e) {
        syncErr = e.toString();
      }
      if (!mounted) return;
      context.go(r.AppRoutes.overview);
      final messenger = ScaffoldMessenger.of(context);
      if (syncErr != null && syncErr.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text('Unlocked • Sync issue: $syncErr')));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Cloud unlocked • Sync complete')));
      }
    } on TimeoutException catch (_) {
      setState(() { _error = 'Network timeout while verifying your key. Please try again.'; });
    } finally {
      setState(() { _unlocking = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = fb.FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.split(' ').first ?? 'there';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    _hasWrap ? 'Welcome back, $name' : 'Welcome, $name',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _loading
                        ? 'Checking your cloud key…'
                        : (_hasWrap
                            ? 'Enter your passphrase to unlock cloud sync and load your data.'
                            : (_netError
                                ? 'Cannot verify your cloud key right now. Check your connection and try again.'
                                : 'Looks like this is your first time here. You can set up cloud sync later in Settings → Privacy.')),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_hasWrap)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _ctl,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Cloud key passphrase',
                            suffixIcon: IconButton(
                              tooltip: _obscure ? 'Show' : 'Hide',
                              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                          ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _unlocking ? null : _onUnlock,
                          icon: _unlocking
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.lock_open_outlined),
                          label: Text(_unlocking ? 'Unlocking…' : 'Unlock & Sync'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.go(r.AppRoutes.overview),
                          child: const Text('Skip for now'),
                        ),
                      ],
                    )
                  else if (_netError)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                          ),
                        FilledButton.icon(
                          onPressed: _checkRemoteKey,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.go(r.AppRoutes.welcome),
                          child: const Text('Sign out'),
                        ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: () => context.go(r.AppRoutes.overview),
                          child: const Text('Continue'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.go(r.AppRoutes.profile),
                          child: const Text('Set up cloud sync now'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
