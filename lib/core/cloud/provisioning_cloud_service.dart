import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';

import '../auth/auth_service.dart';
import '../crypto/provisioning_service.dart';
import '../crypto/key_service.dart';

/// Firestore-based E2E provisioning using X25519.
/// Collections under users/{uid}:
/// - devices/{deviceId}: { pubKey: base64, addedAt }
/// - wrap_requests/{deviceId}: { receiverPubKey: base64, createdAt }
/// - wrapped_mk/{deviceId}: { blob: `<json>`, createdAt }
class ProvisioningCloudService {
  ProvisioningCloudService._();
  static final ProvisioningCloudService instance = ProvisioningCloudService._();

  final _db = FirebaseFirestore.instance;
  bool _approverActive = false;

  String get _uid => AuthService.instance.currentUser!.uid;

  Future<void> _publishDevice() async {
    try {
      final devId = await ProvisioningService.instance.deviceId();
      final pub = await ProvisioningService.instance.publicKey();
      final doc = _db.collection('users').doc(_uid).collection('devices').doc(devId);
      await doc.set({
        'pubKey': base64Encode(pub.bytes),
        'addedAt': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Start listening for wrap requests and respond automatically if MK is present.
  Future<void> startApprover() async {
    if (_approverActive) return;
    _approverActive = true;
    await _publishDevice();
    try {
      final col = _db.collection('users').doc(_uid).collection('wrap_requests');
      col.snapshots().listen((snap) async {
        for (final doc in snap.docs) {
          final targetDevId = doc.id;
          // Skip if it's our own device id
          final myId = await ProvisioningService.instance.deviceId();
          if (targetDevId == myId) continue;
          // Only proceed if we have MK locally
          final hasMk = await KeyService.instance.hasMasterKey();
          if (!hasMk) continue;
          try {
            final data = doc.data();
            final b64 = data['receiverPubKey'] as String?;
            if (b64 == null) continue;
            final receiver = SimplePublicKey(base64Decode(b64), type: KeyPairType.x25519);
            final wrapped = await ProvisioningService.instance.wrapMasterKeyFor(receiverPublicKey: receiver);
            await _db.collection('users').doc(_uid).collection('wrapped_mk').doc(targetDevId).set({
              'blob': wrapped,
              'createdAt': DateTime.now().millisecondsSinceEpoch,
            });
            // Best-effort cleanup
            await doc.reference.delete();
          } catch (_) {
            // ignore and continue
          }
        }
      });
    } catch (_) {
      // ignore if Firestore not available
    }
  }

  /// If this device lacks MK, tries to fetch a wrapped MK from Firestore and install it.
  Future<bool> tryCloudAutoUnlock() async {
    try {
      final devId = await ProvisioningService.instance.deviceId();
      final doc = await _db.collection('users').doc(_uid).collection('wrapped_mk').doc(devId).get();
      final data = doc.data();
      if (data == null) return false;
      final blob = Map<String, dynamic>.from(data['blob'] as Map);
      final mkBytes = await ProvisioningService.instance.unwrapMasterKey(blob);
      await KeyService.instance.setMasterKey(mkBytes);
      // Cleanup the wrapped blob after successful import
      try { await doc.reference.delete(); } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Creates a wrap request so another signed-in device can wrap the MK for us.
  Future<void> requestWrapForThisDevice() async {
    try {
      final devId = await ProvisioningService.instance.deviceId();
      final pub = await ProvisioningService.instance.publicKey();
      await _db.collection('users').doc(_uid).collection('wrap_requests').doc(devId).set({
        'receiverPubKey': base64Encode(pub.bytes),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  /// Called after sign-in to wire everything up.
  Future<void> onSignedIn() async {
    await _publishDevice();
    await startApprover();
  }
}
