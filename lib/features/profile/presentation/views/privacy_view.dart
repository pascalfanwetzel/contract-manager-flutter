import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../../../contracts/data/app_state.dart';
import '../../../../core/crypto/passphrase_service.dart';

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
                subtitle: const Text('Attachments are encrypted at rest. Nothing is uploaded unless you export.'),
              ),
            ),
            const SizedBox(height: 12),

            const Text('Security', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
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
                  const Divider(height: 1),
                  FutureBuilder<bool>(
                    future: PassphraseService.hasPassphrase(),
                    builder: (context, snapshot) {
                      final has = snapshot.data == true;
                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.key_outlined),
                            title: const Text('Encryption Passphrase (for exports)'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Protect exported backups (zip) with a passphrase'),
                                if (has)
                                  FutureBuilder<DateTime?>(
                                    future: PassphraseService.passphraseSetAt(),
                                    builder: (context, snap) {
                                      final dt = snap.data;
                                      if (dt == null) return const SizedBox.shrink();
                                      String two(int n) => n.toString().padLeft(2, '0');
                                      final stamp = '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text('Last set on $stamp', style: Theme.of(context).textTheme.bodySmall),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            onTap: () async {
                              if (has) {
                                final ok = await _confirm(
                                  context,
                                  'Change passphrase?',
                                  'Changing your export passphrase will not affect existing exports. Previously exported backups will still require the old passphrase.',
                                );
                                if (ok != true) return;
                              }
                              final pass = await _promptForPassphrase(context);
                              if (pass == null) return;
                              await PassphraseService.setPassphrase(pass);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passphrase saved')));
                                setState(() {}); // refresh last-set timestamp
                              }
                            },
                          ),
                          if (has) const Divider(height: 1),
                          if (has)
                            ListTile(
                              leading: const Icon(Icons.no_encryption_outlined),
                              title: const Text('Remove Encryption Passphrase'),
                              subtitle: const Text('Delete locally stored encrypted master key'),
                              onTap: () async {
                                final ok = await _confirm(context, 'Remove passphrase?', 'This deletes the encrypted master key (EMK) file. It does not change on-device encryption.');
                                if (ok == true) {
                                  await PassphraseService.clearPassphrase();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passphrase removed')));
                                    setState(() {}); // refresh section
                                  }
                                }
                              },
                            ),
                        ],
                      );
                    },
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
                  // Only notifications are requested by this app; camera and storage
                  // use system intents and app-private storage respectively.
                  _permTile('Notifications', Icons.notifications_outlined, Permission.notification),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Text('Data Management', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            // Export data
            Card(
              child: ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Export data'),
                trailing: IconButton(
                  tooltip: 'What gets exported?',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => _infoDialog(
                    context,
                    'Export data',
                    'Exports all app data (contracts, notes, settings, attachments) into a zip file.\n\nSecurity: You will be asked to set an encryption passphrase (if not already set). The passphrase protects the exported zip.',
                  ),
                ),
                onTap: () async {
                      // Capture messenger before awaits to avoid context-after-await
                      final messenger = ScaffoldMessenger.of(context);
                      // Enforce passphrase-protected exports
                      var has = await PassphraseService.hasPassphrase();
                      if (!context.mounted) return;
                      if (!has) {
                        final set = await _confirm(context, 'Set passphrase?', 'To make your backup portable and secure, please set an encryption passphrase first.');
                        if (!context.mounted) return;
                        if (set == true) {
                          final pass = await _promptForPassphrase(context);
                          if (!context.mounted) return;
                          if (pass == null) return;
                          await PassphraseService.setPassphrase(pass);
                          has = true;
                        } else {
                          return;
                        }
                      }
                      final ok = await _confirm(context, 'Export data?', 'Create an export zip in app documents folder?');
                      if (!context.mounted) return;
                      if (ok != true) return;
                      final path = await state.exportAll();
                      if (!context.mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Export saved to $path'),
                          action: SnackBarAction(
                            label: 'Open',
                            onPressed: () async {
                              // Try opening the folder; fall back to the file
                              final dirPath = File(path).parent.path;
                              final openedDir = await launchUrl(Uri.file(dirPath), mode: LaunchMode.externalApplication);
                              if (!openedDir) {
                                await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                        ),
                      );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Import data
            Card(
              child: ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('Import Data'),
                trailing: IconButton(
                  tooltip: 'What gets imported?',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => _infoDialog(
                    context,
                    'Import Data',
                    'Replaces your current data with a previously exported zip.\n\nSecurity: If the export was protected, you will need the encryption passphrase to restore.',
                  ),
                ),
                onTap: () async {
                      // Capture messenger before awaits to avoid context-after-await lint
                      final messenger = ScaffoldMessenger.of(context);
                      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
                      final zipPath = picked?.files.single.path;
                      if (zipPath == null) return;
                      if (!context.mounted) return;
                      final ok = await _confirm(context, 'Restore data?', 'This will replace your current contracts, notes, settings and attachments. Continue?');
                      if (!context.mounted) return;
                      if (ok != true) return;
                      final pass = await _promptForUnlockPassphrase(context);
                      if (!context.mounted) return;
                      if (pass == null || pass.trim().isEmpty) return; // enforce passphrase for imports
                      final ok2 = await state.importFromZip(zipPath, passphrase: pass.trim());
                      if (!context.mounted) return;
                      messenger.showSnackBar(SnackBar(
                        content: Text(ok2
                            ? 'Data restored from export'
                            : 'Import failed: wrong/missing passphrase or invalid archive'),
                      ));
                },
              ),
            ),
            const SizedBox(height: 12),
            // Wipe data
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Wipe local data'),
                trailing: IconButton(
                  tooltip: 'What gets wiped?',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => _infoDialog(
                    context,
                    'Wipe local data',
                    'Deletes contracts, notes, settings, attachments and cached thumbnails from this device. This does not affect any external backups you may have exported.',
                  ),
                ),
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

Future<void> _infoDialog(BuildContext context, String title, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

Future<String?> _promptForPassphrase(BuildContext context) {
  final passCtl = TextEditingController();
  final confirmCtl = TextEditingController();
  String? error;
  bool obscured = true;
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('Encryption Passphrase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passCtl,
                obscureText: obscured,
                decoration: const InputDecoration(labelText: 'Passphrase'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtl,
                obscureText: obscured,
                decoration: const InputDecoration(labelText: 'Confirm passphrase'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => obscured = !obscured),
                  icon: Icon(obscured ? Icons.visibility_off : Icons.visibility),
                  label: Text(obscured ? 'Show' : 'Hide'),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final p1 = passCtl.text.trim();
                final p2 = confirmCtl.text.trim();
                if (p1.length < 8) {
                  setState(() => error = 'Use at least 8 characters');
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
      });
    },
  );
}

Future<String?> _promptForUnlockPassphrase(BuildContext context) {
  final ctl = TextEditingController();
  bool obscured = true;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      return AlertDialog(
        title: const Text('Unlock Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctl,
              obscureText: obscured,
              decoration: const InputDecoration(
                labelText: 'Passphrase (leave blank if not set)',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => obscured = !obscured),
                icon: Icon(obscured ? Icons.visibility_off : Icons.visibility),
                label: Text(obscured ? 'Show' : 'Hide'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Skip')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Unlock')),
        ],
      );
    }),
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

