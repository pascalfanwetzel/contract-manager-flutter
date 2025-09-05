import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../contracts/data/app_state.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../../../core/crypto/keyring_service.dart';

// Private to this library: cloud key setup choices
enum _CloudKeyChoice { enter, useCode, create, cancel }

class PrivacyView extends StatefulWidget {
  final AppState state;
  const PrivacyView({super.key, required this.state});

  @override
  State<PrivacyView> createState() => _PrivacyViewState();
}

class _PrivacyViewState extends State<PrivacyView> {
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isSignedIn = fb.FirebaseAuth.instance.currentUser != null;
    final hasDek = state.hasCloudDek;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Your data stays on this device'),
                subtitle: const Text('Attachments are encrypted at rest. Nothing is uploaded.'),
              ),
            ),
            const SizedBox(height: 12),

            const Text('Security', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Cloud sync (Firebase)'),
                    subtitle: const Text('Keep data synced across devices. Off by default.'),
                    value: state.cloudSyncEnabled,
                    onChanged: (v) async {
                      final messenger = ScaffoldMessenger.of(context);
                      if (!v) {
                        state.setCloudSyncEnabled(false);
                        return;
                      }
                      // Turning ON: ensure prerequisites
                      if (!isSignedIn) {
                        if (!context.mounted) return;
                        messenger.showSnackBar(const SnackBar(content: Text('Sign in to enable cloud sync')));
                        return;
                      }
                      if (hasDek) {
                        state.setCloudSyncEnabled(true);
                        // Optional: kick a sync
                        Future.microtask(() => state.syncNow());
                        return;
                      }
                      // Prompt for cloud key setup (Enter/Create/Use Code)
                      final choice = await _promptCloudKeyChoice(context);
                      if (!context.mounted) return;
                      if (choice == _CloudKeyChoice.enter) {
                        final ok = await _enterCloudKey(context, state);
                        if (ok) {
                          state.setCloudSyncEnabled(true);
                          Future.microtask(() => state.syncNow());
                        }
                      } else if (choice == _CloudKeyChoice.useCode) {
                        final ok = await _enterRecoveryCode(context, state);
                        if (ok) {
                          state.setCloudSyncEnabled(true);
                          Future.microtask(() => state.syncNow());
                        }
                      } else if (choice == _CloudKeyChoice.create) {
                        final ok = await _setCloudKey(context, state);
                        if (ok) {
                          state.setCloudSyncEnabled(true);
                          Future.microtask(() => state.syncNow());
                        }
                      } // cancel -> do nothing, switch remains OFF
                    },
                  ),
                  if (state.cloudSyncEnabled && !isSignedIn) const Divider(height: 1),
                  if (state.cloudSyncEnabled && !isSignedIn)
                    ListTile(
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: const Text('Sign in to enable cloud sync'),
                      subtitle: const Text('You are not signed in. Sync will be local-only and won’t upload until you sign in.'),
                    ),
                  if (state.cloudSyncEnabled && isSignedIn && !hasDek) const Divider(height: 1),
                  if (state.cloudSyncEnabled && isSignedIn && !hasDek)
                    ListTile(
                      leading: const Icon(Icons.vpn_key_outlined),
                      title: const Text('Finish cloud key setup'),
                      subtitle: const Text('Set or enter your cloud key passphrase to enable sync.'),
                      trailing: Wrap(spacing: 8, children: [
                        OutlinedButton(
                          onPressed: () => _enterCloudKey(context, state),
                          child: const Text('Enter'),
                        ),
                        FilledButton(
                          onPressed: () => _setCloudKey(context, state),
                          child: const Text('Create'),
                        ),
                      ]),
                    ),
                  if (state.cloudSyncEnabled && isSignedIn && hasDek)
                    ListTile(
                      leading: const Icon(Icons.manage_accounts_outlined),
                      title: const Text('Cloud key passphrase'),
                      subtitle: const Text('Change your cloud key passphrase.'),
                      trailing: FilledButton(
                        onPressed: () => _changeCloudKey(context, state),
                        child: const Text('Change'),
                      ),
                    ),
                  if (state.cloudSyncEnabled && isSignedIn && hasDek)
                    ListTile(
                      leading: const Icon(Icons.security_outlined),
                      title: const Text('Recovery code'),
                      subtitle: const Text('Generate a one‑time recovery code to unlock your cloud key if you forget your passphrase.'),
                      trailing: FilledButton(
                        onPressed: () => _generateRecoveryCode(context, state),
                        child: const Text('Generate'),
                      ),
                    ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Block screenshots in viewer'),
                    value: state.blockScreenshots,
                    onChanged: (v) => state.setBlockScreenshots(v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Allow Share'),
                    subtitle: const Text('Permit sharing attachments to other apps'),
                    value: state.allowShare,
                    onChanged: (v) => state.setAllowShare(v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Allow Download'),
                    subtitle: const Text('Permit saving decrypted copies to device'),
                    value: state.allowDownload,
                    onChanged: (v) => state.setAllowDownload(v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Text('Permissions', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  _permTile('Notifications', Icons.notifications_outlined, Permission.notification),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Text('Data Management', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Wipe local data'),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await _confirm(context, 'Wipe all data?', 'This will delete all local app data. This cannot be undone.');
                  if (!context.mounted) return;
                  if (ok == true) {
                    await state.wipeLocalData();
                    if (!context.mounted) return;
                    messenger.showSnackBar(const SnackBar(content: Text('Local data wiped')));
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            if (state.cloudSyncEnabled)
              Card(
                child: ListTile(
                  leading: Icon(state.isSyncing ? Icons.sync : Icons.cloud_sync_outlined),
                  title: const Text('Sync now'),
                  subtitle: Text(!isSignedIn
                      ? 'Sign in to sync your data'
                      : (!hasDek ? 'Finish cloud key setup to enable sync' : _syncStatusText(state))),
                  onTap: (state.isSyncing || !isSignedIn || !hasDek)
                      ? null
                      : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await state.syncNow();
                        if (!context.mounted) return;
                        final err = state.lastSyncError;
                        if (err != null && err.isNotEmpty) {
                          messenger.showSnackBar(SnackBar(content: Text('Sync failed: $err')));
                        } else {
                          messenger.showSnackBar(const SnackBar(content: Text('Sync complete')));
                        }
                      },
                  trailing: state.isSyncing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                ),
              ),
            if (state.cloudSyncEnabled) const SizedBox(height: 8),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('Export encrypted backup'),
                  subtitle: const Text('Saves an encrypted .enc file (Android: Downloads)'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final pass = await _promptText(context, 'Backup Passphrase', 'Enter a passphrase to encrypt the backup');
                    if (!context.mounted) return;
                    if (pass == null || pass.isEmpty) return;
                    if (pass.length < 8) {
                      if (!context.mounted) return;
                      messenger.showSnackBar(const SnackBar(content: Text('Passphrase must be at least 8 characters')));
                      return;
                    }
                    try {
                      final path = await state.exportEncryptedBackupToDownloads(pass);
                      if (!context.mounted) return;
                      messenger.showSnackBar(SnackBar(content: Text('Backup saved to: $path')));
                    } catch (e) {
                      if (!context.mounted) return;
                      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('Restore encrypted backup'),
                  subtitle: const Text('Pick a .enc backup file and enter the passphrase'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['enc'],
                      );
                      if (!context.mounted) return;
                      if (result == null || result.files.isEmpty) return;
                      final path = result.files.single.path;
                      if (path == null || path.isEmpty) {
                        if (!context.mounted) return;
                        messenger.showSnackBar(const SnackBar(content: Text('Could not access selected file')));
                        return;
                      }
                      if (!context.mounted) return;
                      final pass = await _promptText(context, 'Backup Passphrase', 'Enter the passphrase used for backup');
                      if (!context.mounted) return;
                      if (pass == null || pass.isEmpty) return;
                      if (pass.length < 8) {
                        if (!context.mounted) return;
                        messenger.showSnackBar(const SnackBar(content: Text('Passphrase must be at least 8 characters')));
                        return;
                      }
                      bool ok = false;
                      try {
                        ok = await state.importEncryptedBackupFromPath(path, pass);
                      } on WrongPassphraseError {
                        if (!context.mounted) return;
                        messenger.showSnackBar(const SnackBar(content: Text('Wrong passphrase')));
                        return;
                      } on FormatException catch (e) {
                        if (!context.mounted) return;
                        messenger.showSnackBar(SnackBar(content: Text('Invalid backup: ${e.message}')));
                        return;
                      }
                      if (!context.mounted) return;
                      messenger.showSnackBar(SnackBar(content: Text(ok ? 'Restore complete' : 'Restore failed')));
                    } catch (e) {
                      if (!context.mounted) return;
                      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
                    }
                  },
                ),
              ]),
            ),

            const SizedBox(height: 16),
            const Text('Transparency & Legal', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.policy_outlined),
                    title: const Text('Datenschutzerklärung'),
                    onTap: () => _openTextPage(context, 'Datenschutzerklärung', 'Hier steht Ihre Datenschutzerklärung …'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Impressum'),
                    onTap: () => _openTextPage(context, 'Impressum', 'Hier steht Ihr Impressum …'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirm(BuildContext context, String title, String message) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
      ],
    ),
  );
  }

  Widget _permTile(String title, IconData icon, Permission p) {
  return FutureBuilder<PermissionStatus>(
    future: p.status,
    builder: (context, snapshot) {
      final status = snapshot.data;
      final granted = status == PermissionStatus.granted || status == PermissionStatus.limited;
      return ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(granted ? 'Granted' : 'Not granted'),
        trailing: TextButton(
          onPressed: () => openAppSettings(),
          child: const Text('Open settings'),
        ),
      );
    },
  );
  }

  Future<String?> _promptText(BuildContext context, String title, String message) async {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 8),
          TextField(controller: ctl),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
  }

  void _openTextPage(BuildContext context, String title, String text) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text),
      )),
    ),
  );
  }

  String _syncStatusText(AppState state) {
  if (state.isSyncing) return 'Syncing…';
  if (state.lastSyncError != null) return 'Last error: ${state.lastSyncError}';
  final ts = state.lastSyncTs;
  if (ts == null) return 'Not synced yet';
  final dt = DateTime.fromMillisecondsSinceEpoch(ts);
  final f = DateFormat('y-MM-dd HH:mm');
  return 'Last sync: ${f.format(dt)}';
  }

  

  Future<_CloudKeyChoice> _promptCloudKeyChoice(BuildContext context) async {
  return await showDialog<_CloudKeyChoice>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable Cloud Sync'),
          content: const Text('To keep your data end-to-end encrypted across devices, enter your existing cloud key passphrase, use a recovery code, or create a new one.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, _CloudKeyChoice.cancel), child: const Text('Cancel')),
            OutlinedButton(onPressed: () => Navigator.pop(ctx, _CloudKeyChoice.enter), child: const Text('Enter Passphrase')),
            OutlinedButton(onPressed: () => Navigator.pop(ctx, _CloudKeyChoice.useCode), child: const Text('Use Recovery Code')),
            FilledButton(onPressed: () => Navigator.pop(ctx, _CloudKeyChoice.create), child: const Text('Create New')),
          ],
        ),
      ) ??
      _CloudKeyChoice.cancel;
  }

  Future<bool> _enterCloudKey(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!context.mounted) return false;
      messenger.showSnackBar(const SnackBar(content: Text('Sign in first')));
      return false;
    }
    final pass = await _promptPassphrase(context, title: 'Enter Cloud Key Passphrase');
    if (pass == null) return false;
    try {
      final wrap = await KeyringService.instance.fetchPassphraseWrap(user.uid, throwOnError: true);
      if (wrap == null) {
        if (!context.mounted) return false;
        messenger.showSnackBar(const SnackBar(content: Text('No cloud key set yet. Create one instead.')));
        return false;
      }
      final dek = await KeyringService.instance.unwrapDekWithPassphrase(wrap, pass);
      await KeyringService.instance.setLocalDek(dek);
      state.setCloudDekAvailable(true);
      if (!context.mounted) return true;
      messenger.showSnackBar(const SnackBar(content: Text('Cloud key unlocked')));
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      final msg = e.toString().contains('network') || e.toString().contains('unavailable')
          ? 'Cannot verify your cloud key. Check your connection.'
          : 'Wrong passphrase';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      return false;
    }
  }

  Future<bool> _setCloudKey(BuildContext context, AppState state) async {
  final messenger = ScaffoldMessenger.of(context);
  final user = fb.FirebaseAuth.instance.currentUser;
  if (user == null) {
    if (!context.mounted) return false;
    messenger.showSnackBar(const SnackBar(content: Text('Sign in first')));
    return false;
  }
  // Guard: verify server shows no existing cloud key before creating a new one
  try {
    final existing = await KeyringService.instance.fetchPassphraseWrap(user.uid, throwOnError: true);
    if (existing != null) {
      if (!context.mounted) return false;
      messenger.showSnackBar(const SnackBar(content: Text('A cloud key already exists. Enter your passphrase instead.')));
      return false;
    }
  } catch (_) {
    if (!context.mounted) return false;
    messenger.showSnackBar(const SnackBar(content: Text('Cannot verify cloud key status. Please try again when online.')));
    return false;
  }
  // Confirm creating new passphrase
  if (!context.mounted) return false;
  final pass = await _promptNewPassphrase(context);
  if (!context.mounted) return false;
  if (pass == null) return false;
  try {
    // Use existing DEK if any, else generate
    var dek = await KeyringService.instance.getLocalDek();
    dek ??= await KeyringService.instance.generateDek();
    await KeyringService.instance.setLocalDek(dek);
    final wrapped = await KeyringService.instance.wrapDekWithPassphrase(dek, pass);
    await KeyringService.instance.uploadPassphraseWrap(user.uid, wrapped);
    state.setCloudDekAvailable(true);
    if (!context.mounted) return true;
    messenger.showSnackBar(const SnackBar(content: Text('Cloud key created and synced')));
    // Optional: trigger a sync tick if enabled
    if (state.cloudSyncEnabled) {
      // fire-and-forget
      Future.microtask(() => state.syncNow());
    }
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    messenger.showSnackBar(SnackBar(content: Text('Failed to create cloud key: $e')));
    return false;
  }
  }

  Future<void> _changeCloudKey(BuildContext context, AppState state) async {
  final messenger = ScaffoldMessenger.of(context);
  final user = fb.FirebaseAuth.instance.currentUser;
  if (user == null) {
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Sign in first')));
    return;
  }
    // Require existing DEK
    final dek = await KeyringService.instance.getLocalDek();
    if (!context.mounted) return;
    if (dek == null) {
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('No local cloud key. Enter existing passphrase or create a new one.')));
      return;
    }
    if (!context.mounted) return;
    final pass = await _promptNewPassphrase(context, title: 'Change Cloud Key Passphrase');
    if (!context.mounted) return;
    if (pass == null) return;
    final wrapped = await KeyringService.instance.wrapDekWithPassphrase(dek, pass);
    await KeyringService.instance.uploadPassphraseWrap(user.uid, wrapped);
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Cloud key passphrase updated')));
  }

  Future<void> _generateRecoveryCode(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Sign in first')));
      return;
    }
    final dek = await KeyringService.instance.getLocalDek();
    if (dek == null) {
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Set or enter your cloud key first')));
      return;
    }
    final code = await KeyringService.instance.generateRecoveryCode();
    final wrapped = await KeyringService.instance.wrapDekWithRecoveryCode(dek, code);
    await KeyringService.instance.uploadRecoveryWrap(user.uid, wrapped);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Recovery Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Save this code in a safe place. It can unlock your cloud key if you forget your passphrase. Anyone with this code can decrypt your data.'),
            const SizedBox(height: 12),
            SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
            },
            child: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<bool> _enterRecoveryCode(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!context.mounted) return false;
      messenger.showSnackBar(const SnackBar(content: Text('Sign in first')));
      return false;
    }
    final code = await _promptText(context, 'Use Recovery Code', 'Enter the recovery code you saved');
    if (code == null || code.isEmpty) return false;
    Map<String, dynamic>? wrap;
    try {
      wrap = await KeyringService.instance.fetchRecoveryWrap(user.uid, throwOnError: true);
      if (wrap == null) {
        if (!context.mounted) return false;
        messenger.showSnackBar(const SnackBar(content: Text('No recovery code on file. Generate one first.')));
        return false;
      }
    } catch (_) {
      if (!context.mounted) return false;
      messenger.showSnackBar(const SnackBar(content: Text('Cannot verify recovery code. Check your connection.')));
      return false;
    }
    try {
      final dek = await KeyringService.instance.unwrapDekWithRecoveryCode(wrap, code);
      await KeyringService.instance.setLocalDek(dek);
      state.setCloudDekAvailable(true);
      if (!context.mounted) return true;
      messenger.showSnackBar(const SnackBar(content: Text('Cloud key unlocked via recovery code')));
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      messenger.showSnackBar(const SnackBar(content: Text('Invalid recovery code')));
      return false;
    }
  }

  Future<String?> _promptPassphrase(BuildContext context, {required String title}) async {
  final ctl = TextEditingController();
  bool obscure = true;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the passphrase you created for your cloud key.'),
            const SizedBox(height: 8),
            TextField(
              controller: ctl,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: 'Passphrase',
                suffixIcon: IconButton(
                  tooltip: obscure ? 'Show' : 'Hide',
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => obscure = !obscure),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Unlock')),
        ],
      ),
    ),
  );
  }

  Future<String?> _promptNewPassphrase(BuildContext context, {String title = 'Create Cloud Key Passphrase'}) async {
  final ctl1 = TextEditingController();
  final ctl2 = TextEditingController();
  String? error;
  // Keep visibility state outside the builder so it persists across setState calls
  bool obscure1 = true;
  bool obscure2 = true;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        (double, String, Color) meter(String s) {
          final len = s.length;
          final hasLower = RegExp(r'[a-z]').hasMatch(s);
          final hasUpper = RegExp(r'[A-Z]').hasMatch(s);
          final hasDigit = RegExp(r'\d').hasMatch(s);
          final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(s);
          int variety = [hasLower, hasUpper, hasDigit, hasSymbol].where((b) => b).length;
          double score = 0;
          if (len >= 8) score += 0.3;
          if (len >= 12) score += 0.3; // encourage 12+
          if (len >= 16) score += 0.2; // excellent territory
          score += (variety / 4) * 0.2; // up to +0.2 for variety
          if (len < 8) { return (score.clamp(0.0, 1.0), 'Very weak (use 8+)', Colors.red); }
          if (len < 10) { return (score, 'Weak', Colors.redAccent); }
          if (len < 12) { return (score, 'Fair', Colors.orange); }
          if (len < 16) { return (score, 'Good (12+ recommended)', Colors.green); }
          return (score, 'Excellent (16+)', Colors.teal);
        }
        final p1 = ctl1.text.trim();
        final (val, label, color) = meter(p1);
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your passphrase protects the cloud encryption key. Minimum 8 characters. A longer passphrase (12+ / 16+) is strongly recommended. Keep it safe — it is required to set up new devices.'),
              const SizedBox(height: 12),
              TextField(
                controller: ctl1,
                obscureText: obscure1,
                decoration: InputDecoration(
                  labelText: 'New passphrase',
                  suffixIcon: IconButton(
                    tooltip: obscure1 ? 'Show' : 'Hide',
                    icon: Icon(obscure1 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => obscure1 = !obscure1),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              // Strength meter
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: val.clamp(0.05, 1.0), backgroundColor: Colors.black12, color: color, minHeight: 6),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(color: color)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctl2,
                obscureText: obscure2,
                decoration: InputDecoration(
                  labelText: 'Confirm passphrase',
                  suffixIcon: IconButton(
                    tooltip: obscure2 ? 'Show' : 'Hide',
                    icon: Icon(obscure2 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => obscure2 = !obscure2),
                  ),
                ),
              ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final p1 = ctl1.text.trim();
                final p2 = ctl2.text.trim();
                if (p1.length < 8) {
                  setState(() => error = 'Passphrase must be at least 8 characters');
                  return;
                }
                if (p1 != p2) {
                  setState(() => error = 'Passphrases do not match');
                  return;
                }
                Navigator.pop(ctx, p1);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  }
}
