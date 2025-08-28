import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../contracts/data/app_state.dart';

class PrivacyView extends StatelessWidget {
  final AppState state;
  const PrivacyView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (_, __) {
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
                  SwitchListTile(
                    title: const Text('Require biometric for export'),
                    subtitle: const Text('Ask for FaceID/TouchID or device PIN before Share/Download'),
                    value: state.requireBiometricExport,
                    onChanged: (v) => state.setRequireBiometricExport(v),
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
                  _permTile('Camera', Icons.camera_alt_outlined, Permission.camera),
                  const Divider(height: 1),
                  _permTile('Notifications', Icons.notifications_outlined, Permission.notification),
                  if (Platform.isAndroid) const Divider(height: 1),
                  if (Platform.isAndroid)
                    _permTile('Storage', Icons.folder_outlined, Permission.storage),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Text('Data Management', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: const Text('Export data'),
                    subtitle: const Text('Export notes, settings and attachments (encrypted)'),
                    onTap: () async {
                      final ok = await _confirm(context, 'Export data?', 'Create an export zip in app documents folder?');
                      if (ok != true) return;
                      final path = await state.exportAll();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Export saved to $path')),
                        );
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_outlined),
                    title: const Text('Wipe local data'),
                    subtitle: const Text('Delete notes, settings, attachments and cached thumbnails'),
                    onTap: () async {
                      final ok = await _confirm(context, 'Wipe all data?', 'This will delete all local app data. This cannot be undone.');
                      if (ok == true) {
                        await state.wipeLocalData();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local data wiped')));
                        }
                      }
                    },
                  ),
                ],
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
