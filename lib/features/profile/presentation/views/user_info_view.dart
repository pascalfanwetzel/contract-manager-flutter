import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../contracts/data/app_state.dart';
import '../../data/user_profile.dart';

class UserInfoView extends StatefulWidget {
  final AppState state;
  const UserInfoView({super.key, required this.state});

  @override
  State<UserInfoView> createState() => _UserInfoViewState();
}

class _UserInfoViewState extends State<UserInfoView> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String? _locale;
  String? _currency;
  String? _country;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _syncFromState();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _syncFromState() {
    final p = widget.state.profile;
    _name.text = p.name;
    _email.text = p.email;
    _phone.text = p.phone ?? '';
    _locale = p.locale;
    _currency = p.currency;
    _country = p.country;
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final p = widget.state.profile.copyWith(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        locale: _locale,
        currency: _currency,
        country: _country,
      );
      await widget.state.updateProfile(p);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (_, __) {
        final p = widget.state.profile;
        // keep form in sync if state changed elsewhere
        if (_name.text != p.name || _email.text != p.email || _phone.text != (p.phone ?? '')) {
          _syncFromState();
        }
        final avatar = p.photoPath != null && p.photoPath!.isNotEmpty ? File(p.photoPath!) : null;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: avatar != null ? FileImage(avatar) : null,
                    child: avatar == null
                        ? (p.name.trim().isEmpty
                            ? const Icon(Icons.person, size: 36)
                            : Text(p.initials, style: const TextStyle(fontSize: 24)))
                        : null,
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final picker = ImagePicker();
                      final img = await picker.pickImage(source: ImageSource.gallery);
                      if (img != null) {
                        await widget.state.setProfileAvatarFromPath(img.path);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              onChanged: (_) => _scheduleSave(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              onChanged: (_) => _scheduleSave(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
              onChanged: (_) => _scheduleSave(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _locale,
              decoration: const InputDecoration(labelText: 'Locale'),
              items: [
                DropdownMenuItem(value: 'en-US', child: Text('English (US)')),
                DropdownMenuItem(value: 'en-GB', child: Text('English (UK)')),
                DropdownMenuItem(value: 'de-DE', child: Text('Deutsch (DE)')),
              ],
              onChanged: (v) {
                setState(() => _locale = v);
                _scheduleSave();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: [
                DropdownMenuItem(value: 'EUR', child: Text('EUR €')),
                DropdownMenuItem(value: 'USD', child: Text('USD \$')),
                DropdownMenuItem(value: 'GBP', child: Text('GBP £')),
              ],
              onChanged: (v) {
                setState(() => _currency = v);
                _scheduleSave();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _country,
              decoration: const InputDecoration(labelText: 'Country'),
              items: [
                DropdownMenuItem(value: 'US', child: Text('United States')),
                DropdownMenuItem(value: 'DE', child: Text('Germany')),
                DropdownMenuItem(value: 'GB', child: Text('United Kingdom')),
              ],
              onChanged: (v) {
                setState(() => _country = v);
                _scheduleSave();
              },
            ),
          ],
        );
      },
    );
  }
}
