import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'storage_info_view.dart';
import '../../../contracts/data/app_state.dart';

class HelpFeedbackView extends StatefulWidget {
  final AppState state;
  const HelpFeedbackView({super.key, required this.state});

  @override
  State<HelpFeedbackView> createState() => _HelpFeedbackViewState();
}

class _HelpFeedbackViewState extends State<HelpFeedbackView> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((v) => setState(() => _info = v));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How can we help?', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ActionChip(
                      icon: Icons.rate_review_outlined,
                      label: 'Send feedback',
                      onTap: () => _sendEmail(subject: 'Feedback: Contract Manager'),
                    ),
                    _ActionChip(
                      icon: Icons.bug_report_outlined,
                      label: 'Report a bug',
                      onTap: () => _sendEmail(subject: 'Bug Report: Contract Manager'),
                    ),
                    _ActionChip(
                      icon: Icons.lightbulb_outline,
                      label: 'Request a feature',
                      onTap: () => _sendEmail(subject: 'Feature Request: Contract Manager'),
                    ),
                    _ActionChip(
                      icon: Icons.star_rate_outlined,
                      label: 'Rate the app',
                      onTap: _rateApp,
                    ),
                    _ActionChip(
                      icon: Icons.folder_open_outlined,
                      label: 'Storage info',
                      onTap: _openStorageInfo,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('FAQs'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: const [
              _Faq(q: 'Where are my files stored?', a: 'Only on your device in the app\'s private storage. Attachments are encrypted at rest.'),
              _Faq(q: 'How do I export my data?', a: 'Go to Profile â†’ Privacy â†’ Export data to create a zip archive.'),
              _Faq(q: 'Can I change reminder times?', a: 'Yes. Profile â†’ Notifications & Reminders lets you pick lead times and time of day.'),
              _Faq(q: 'How do I delete my data?', a: 'Use Profile â†’ Privacy â†’ Wipe local data to remove everything from this device.'),
            ],
          ),
        ),

        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('Tutorials'),
                subtitle: const Text('Learn the basics and power features'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Getting started'),
                onTap: () => _openDocs(context, 'Getting started',
                    'â€¢ Create your first contract via +\nâ€¢ Open a contract to see Attachments and Notes\nâ€¢ Use Profile â†’ Notifications to set reminders'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.attach_file_outlined),
                title: const Text('Attachments'),
                onTap: () => _openDocs(context, 'Attachments',
                    'Add PDFs or images, or scan via camera. Files are stored encrypted and visible only in the app. Tap to view, rename or delete. '),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.alarm_on_outlined),
                title: const Text('Reminders'),
                onTap: () => _openDocs(context, 'Reminders',
                    'Configure lead times (1/7/14/30 days) and a time of day in Profile â†’ Notifications & Reminders. The app schedules local notifications for contracts with end dates.'),
              ),
            ],
          ),
        ),


        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('Contact support'),
                subtitle: const Text('Open your email app to write to us'),
                onTap: () => _sendEmail(),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Share diagnostics'),
                subtitle: const Text('Create a small report to attach to emails'),
                onTap: () => _exportDiagnostics(context),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App info'),
            subtitle: Text(info == null ? 'Loadingâ€¦' : 'Version ${info.version} (${info.buildNumber})'),
          ),
        ),
      ],
    );
  }

  Future<void> _exportDiagnostics(BuildContext context) async {
    try {
      // Capture context-derived values before async gaps
      final reminderTimeStr = widget.state.reminderTime.format(context);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/diagnostics_${DateTime.now().millisecondsSinceEpoch}.txt');
      final info = _info;
      final buf = StringBuffer()
        ..writeln('Contract Manager diagnostics')
        ..writeln('Generated: ${DateTime.now().toIso8601String()}')
        ..writeln('Version: ${info?.version ?? '-'} (${info?.buildNumber ?? '-'})')
        ..writeln('Theme: ${widget.state.themeMode}')
        ..writeln('Reminders: enabled=${widget.state.remindersEnabled}, days=${widget.state.reminderDays.toList()..sort()}, time=$reminderTimeStr')
        ..writeln('Attachments grid preferred: ${widget.state.attachmentsGridPreferred}')
        ..writeln('AllowShare=${widget.state.allowShare}, AllowDownload=${widget.state.allowDownload}, BlockScreenshots=${widget.state.blockScreenshots}')
        ..writeln('Auto-empty trash: enabled=${widget.state.autoEmptyTrashEnabled}, days=${widget.state.autoEmptyTrashDays}');
      await file.writeAsString(buf.toString(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Diagnostics',
          text: 'Diagnostics report from Contract Manager',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create diagnostics: $e')));
      }
    }
  }

  Future<void> _sendEmail({String subject = 'Support: Contract Manager'}) async {
    final uri = Uri(scheme: 'mailto', path: 'support@example.com', queryParameters: {'subject': subject});
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _rateApp() async {
    try {
      final info = _info ?? await PackageInfo.fromPlatform();
      final package = info.packageName;
      Uri? uri;
      if (Platform.isAndroid) {
        // Try Play Store app first, then fall back to web
        final market = Uri.parse('market://details?id=$package');
        if (await canLaunchUrl(market)) {
          uri = market;
        } else {
          uri = Uri.parse('https://play.google.com/store/apps/details?id=$package');
        }
      } else if (Platform.isIOS) {
        // TODO: replace with your App Store ID
        const appId = '0000000000';
        uri = Uri.parse('https://apps.apple.com/app/id$appId?action=write-review');
      }
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // ignore
    }
  }

  void _openStorageInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StorageInfoView()),
    );
  }

  void _openDocs(BuildContext context, String title, String text) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _Faq extends StatelessWidget {
  final String q;
  final String a;
  const _Faq({required this.q, required this.a});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(q),
      childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      children: [Text(a)],
    );
  }
}


