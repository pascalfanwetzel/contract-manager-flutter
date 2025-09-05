import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'package:http/http.dart' as http;
// path_provider not needed here
import '../fs/app_dirs.dart';
import 'dart:io';

import '../../features/contracts/data/app_state.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;
  // Google Sign-In: use native account picker on Android/iOS via google_sign_in;
  // use Firebase provider popup on Web; use provider on desktop.

  Stream<fb.User?> get userChanges => _auth.userChanges();
  fb.User? get currentUser => _auth.currentUser;

  Future<void> signInWithGoogle() async {
    final provider = fb.GoogleAuthProvider();
    // Web: use Firebase popup flow
    if (kIsWeb) {
      await _auth.signInWithPopup(provider).timeout(const Duration(seconds: 30));
      return;
    }

    // Android / iOS / macOS: prefer native google_sign_in (v7+) flow
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        await _ensureGoogleInitialized();
        if (gsi.GoogleSignIn.instance.supportsAuthenticate()) {
          // v7+: interactive authentication
          final account = await gsi.GoogleSignIn.instance
              .authenticate(scopeHint: const ['email'])
              .timeout(const Duration(seconds: 60));
          final auth = account.authentication; // v7: synchronous object
          final idTok = auth.idToken;
          // Build credential with available tokens (v7 typically provides idToken only)
          final cred = fb.GoogleAuthProvider.credential(
            idToken: (idTok != null && idTok.isNotEmpty) ? idTok : null,
          );
          await _auth.signInWithCredential(cred).timeout(const Duration(seconds: 30));
          return;
        }
        // If authenticate() unsupported (older plugin/platform), fall through to provider flow below
      } on gsi.GoogleSignInException catch (e) {
        debugPrint('[AUTH] google_sign_in signIn() failed: $e');
        // If user canceled the flow, just exit silently.
        if (e.code == gsi.GoogleSignInExceptionCode.canceled) {
          return;
        }
        // Otherwise, fall through to provider-based flow.
      } on TimeoutException catch (_) {
        debugPrint('[AUTH] google_sign_in timed out');
        // Fall through to provider-based flow.
      } on Exception catch (e) {
        debugPrint('[AUTH] google_sign_in exception: $e');
        // Fall through to provider-based flow.
      }
    }

    // Fallback: Firebase provider-based sign-in (desktop or when native flow fails)
    try {
      final hasNet = await _hasNetworkConnectivity();
      if (!hasNet) {
        throw fb.FirebaseAuthException(
          code: 'network-request-failed',
          message: 'No internet connectivity to Google endpoints.',
        );
      }
      await _auth.signInWithProvider(provider).timeout(const Duration(seconds: 60));
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('[AUTH] signInWithProvider failed: ${e.code} ${e.message}');
      rethrow;
    } on TimeoutException catch (_) {
      debugPrint('[AUTH] signInWithProvider timed out');
      rethrow;
    } catch (e) {
      debugPrint('[AUTH] signInWithProvider exception: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    try {
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS)) {
        await _ensureGoogleInitialized();
        // Prefer disconnect to revoke app consent; fall back to signOut
        try {
          await gsi.GoogleSignIn.instance.disconnect();
        } catch (_) {
          await gsi.GoogleSignIn.instance.signOut();
        }
      }
    } catch (_) {}
  }

  bool _gsiInit = false;
  Future<void> _ensureGoogleInitialized() async {
    if (_gsiInit) return;
    try {
      await gsi.GoogleSignIn.instance.initialize();
    } finally {
      _gsiInit = true; // avoid repeated initialize calls
    }
  }

  Future<bool> _hasNetworkConnectivity({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final lookups = await Future.wait<List<InternetAddress>>([
        InternetAddress.lookup('www.googleapis.com'),
        InternetAddress.lookup('accounts.google.com'),
      ]).timeout(timeout);
      return lookups.any((lst) => lst.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Prefills profile fields from Google account on first sign-in if empty.
  Future<void> prefillProfileIfEmpty(AppState state) async {
    final u = _auth.currentUser;
    if (u == null) return;
    final p = state.profile;
    var updated = p;
    // Name + Email
    final name = (p.name.isEmpty) ? (u.displayName ?? '') : p.name;
    final email = (p.email.isEmpty) ? (u.email ?? '') : p.email;
    if (name != p.name || email != p.email) {
      updated = updated.copyWith(name: name, email: email);
    }

    // Phone (if provided by the Firebase user)
    final phone = u.phoneNumber;
    if ((updated.phone == null || updated.phone!.isEmpty) && phone != null && phone.isNotEmpty) {
      updated = updated.copyWith(phone: phone);
    }

    // Language & Country from device locale as a sensible default
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final languageTag = '${locale.languageCode}${locale.countryCode != null && locale.countryCode!.isNotEmpty ? '-${locale.countryCode}' : ''}';
    if ((updated.locale).isEmpty) {
      updated = updated.copyWith(locale: languageTag);
    }
    if ((updated.country).isEmpty) {
      final cc = locale.countryCode ?? 'US';
      updated = updated.copyWith(country: cc);
    }
    // Currency inferred from country if not set
    if ((updated.currency).isEmpty || updated.currency == 'EUR' || updated.currency == 'USD') {
      final cur = _currencyForCountry(updated.country);
      if (cur != null) updated = updated.copyWith(currency: cur);
    }

    // Avatar: download Google photo if present and no local photo yet
    final photoUrl = u.photoURL;
    if ((updated.photoPath == null || updated.photoPath!.isEmpty) && photoUrl != null && photoUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(photoUrl);
        final resp = await http.get(uri);
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final dir = await AppDirs.supportDir();
          final ext = _guessImageExtensionFromContentType(resp.headers['content-type']) ?? _extFromPath(uri.path) ?? 'jpg';
          final f = File('${dir.path}/profile_avatar.$ext');
          await f.writeAsBytes(resp.bodyBytes, flush: true);
          updated = updated.copyWith(photoPath: f.path);
        }
      } catch (_) {}
    }

    if (updated != p) {
      await state.updateProfile(updated);
    }
  }

  String? _currencyForCountry(String? country) {
    if (country == null) return null;
    switch (country.toUpperCase()) {
      case 'US':
        return 'USD';
      case 'GB':
      case 'UK':
        return 'GBP';
      case 'DE':
      case 'FR':
      case 'ES':
      case 'IT':
      case 'NL':
      case 'BE':
      case 'AT':
      case 'IE':
      case 'FI':
      case 'PT':
      case 'GR':
      case 'LU':
      case 'LT':
      case 'LV':
      case 'EE':
      case 'SK':
      case 'SI':
      case 'CY':
      case 'MT':
        return 'EUR';
      case 'PL':
        return 'PLN';
      case 'SE':
        return 'SEK';
      case 'NO':
        return 'NOK';
      case 'DK':
        return 'DKK';
      case 'CH':
        return 'CHF';
      case 'CZ':
        return 'CZK';
      case 'HU':
        return 'HUF';
      case 'RO':
        return 'RON';
      case 'BG':
        return 'BGN';
      case 'IS':
        return 'ISK';
      case 'JP':
        return 'JPY';
      case 'CN':
        return 'CNY';
      case 'IN':
        return 'INR';
      case 'CA':
        return 'CAD';
      case 'AU':
        return 'AUD';
      case 'NZ':
        return 'NZD';
      default:
        return null;
    }
  }

  String? _guessImageExtensionFromContentType(String? ct) {
    switch ((ct ?? '').toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      default:
        return null;
    }
  }

  String? _extFromPath(String path) {
    final parts = path.split('.');
    if (parts.length < 2) return null;
    final ext = parts.last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return ext == 'jpeg' ? 'jpg' : ext;
    return null;
  }
}
