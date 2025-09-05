import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/attachments.dart';
import 'attachment_repository.dart';
import 'contracts_store.dart';
import 'notes_store.dart';
import '../../profile/data/user_profile.dart';
import '../../profile/data/profile_store.dart';
import '../../profile/data/settings_store.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/db/db_service.dart';
import '../../../core/fs/app_dirs.dart';
import '../../../core/cloud/firebase_sync_service.dart';
import '../../../core/cloud/sync_service.dart';
import '../../../core/cloud/sync_registry.dart';
import '../../../core/cloud/snapshot_service.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show ConflictAlgorithm;
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/crypto/keyring_service.dart';
import '../../../core/crypto/blob_crypto.dart';
// Legacy crypto flows removed; DB handles local encryption

class AppState extends ChangeNotifier {
  final AttachmentRepository _attachmentsRepo = AttachmentRepository();
  final ContractsStore _contractsStore = ContractsStore();
  final NotesStore _notesStore = NotesStore();
  final ProfileStore _profileStore = ProfileStore();
  final SettingsStore _settingsStore = SettingsStore();
  SyncService? _sync;
  bool _syncing = false;
  int? _lastSyncTs;
  String? _lastSyncError;
  StreamSubscription? _authSub;
  bool _isRestoring = false;
  bool _hasCloudDek = false;
  bool _saveInProgress = false;
  bool _saveAgain = false;
  Future<void> _lastSave = Future.value();
  // Cloud sync (Firebase) toggle, off by default
  bool _cloudSyncEnabled = false;
  bool _attachmentsGridPreferred = false;
  ThemeMode _themeMode = ThemeMode.system;
  // Initial hydration gate
  bool _isLoading = true;
  bool get isLoading => _isLoading;
  String? _dbErrorMessage;
  String? get dbErrorMessage => _dbErrorMessage;
  bool get hasCloudDek => _hasCloudDek;
  // Locked state removed; DB handles local encryption
  bool get isLocked => false;
  // Reminders & notifications
  bool _remindersEnabled = true;
  bool _pushEnabled = true;
  bool _inAppBannerEnabled = true;
  Set<int> _reminderDays = {1, 7, 14, 30};
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);
  // Privacy controls (defaults)
  bool _blockScreenshots = true;
  bool _allowShare = true;
  bool _allowDownload = true;
  // Biometric settings removed
  final List<ContractGroup> _categories = [
    const ContractGroup(id: 'cat_home', name: 'Home', builtIn: true),
    const ContractGroup(id: 'cat_subs', name: 'Subscriptions', builtIn: true),
    const ContractGroup(id: 'cat_other', name: 'General', builtIn: true),
  ];

  final List<Contract> _contracts = [];

  // Attachments: in-memory index hydrated from filesystem
  final Map<String, List<Attachment>> _attachments = {};
  final Map<String, DateTime> _notesEditedAt = {};
  UserProfile _profile = const UserProfile(
    name: '',
    email: '',
    phone: null,
    locale: 'en-US',
    timezone: 'UTC',
    currency: 'EUR',
    country: 'US',
    photoPath: null,
  );

  AppState() {
    _init();
  }

  Future<void> _init() async {
    try {
      // Ensure DB opens early so we can catch/log any open issues
      try { await DbService.instance.db; } catch (e) {
        if (e is DbOpenError) {
          _dbErrorMessage = e.message;
        }
      }
      await Future.wait([
        _hydrateContracts(),
        _hydrateNotes(),
        _hydrateProfile(),
        _hydrateSettings(),
      ]);
    } catch (_) {}
    _isLoading = false;
    // Start auth listener
    _bindAuthListener();
    // Start sync service if enabled AND signed in; then run an initial sync if we have a DEK
    if (_cloudSyncEnabled && fb.FirebaseAuth.instance.currentUser != null) {
      await _ensureSyncService();
      try { await _sync!.start(); } catch (_) {}
      // Best-effort initial sync to avoid showing "Not synced yet" on launch
      if (_hasCloudDek) {
        try { await syncNow(); } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> rehydrateAll() async {
    _isLoading = true;
    notifyListeners();
    try {
      await Future.wait([
        _hydrateContracts(),
        _hydrateNotes(),
        _hydrateProfile(),
        _hydrateSettings(),
      ]);
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  // Use before a cloud refresh (first unlock/sign-in) to avoid rendering
  // stale in-memory lists while the initial sync + hydration completes.
  void beginFreshCloudHydrate() {
    _isLoading = true;
    _categories.clear();
    _contracts.clear();
    notifyListeners();
  }

  void clearDbError() {
    _dbErrorMessage = null;
    notifyListeners();
  }

  // Unlock check removed; DB handles local encryption

  Future<bool> unlockWithPassphrase(String passphrase) async => true;

  /// Call this after the master key has been installed by an external flow
  /// (e.g., cloud auto-unlock or device provisioning). Rehydrates state.
  Future<void> unlockAfterExternalKeyInstall() async {}

  Future<void> _hydrateContracts() async {
    final snap = await _contractsStore.load();
    if (snap != null) {
      _categories
        ..clear()
        ..addAll(snap.categories);
      // Only seed built-ins on first run while signed out; when signed in, let cloud be authoritative
      final signedIn = fb.FirebaseAuth.instance.currentUser != null;
      if (!signedIn && _categories.isEmpty) {
        _ensureBuiltinCategories();
      }
      // One-time rename: cat_other display name from 'Other' -> 'General'
      final idxOther = _categories.indexWhere((c) => c.id == 'cat_other');
      if (idxOther != -1 && _categories[idxOther].name == 'Other') {
        final old = _categories[idxOther];
        _categories[idxOther] = ContractGroup(
          id: old.id,
          name: 'General',
          builtIn: old.builtIn,
          orderIndex: old.orderIndex,
          iconKey: old.iconKey,
        );
        // Persist rename so DB + sync reflect the new label
        try { await _persistContracts(); } catch (_) {}
      }
      // Load persisted data; keep empty if none
      final loaded = List<Contract>.from(snap.contracts);
      _contracts
        ..clear()
        ..addAll(loaded);
      // Ensure no duplicate category names linger from older versions or remote merges
      _dedupeCategoriesByName();
      notifyListeners();
    } else {
      // First run: if signed out, seed built-ins; otherwise let cloud populate
      final signedIn = fb.FirebaseAuth.instance.currentUser != null;
      _categories.clear();
      if (!signedIn) _ensureBuiltinCategories();
      _contracts.clear();
      notifyListeners();
    }
  }

  // Removed unused _looksLikeDemoSeed helper

  // Demo contracts removed; start with an empty database

  void _ensureBuiltinCategories() {
    // Make sure built-in categories exist at least once
    bool has(String id) => _categories.any((c) => c.id == id);
    if (!has('cat_home')) _categories.insert(0, const ContractGroup(id: 'cat_home', name: 'Home', builtIn: true));
    if (!has('cat_subs')) _categories.insert(1, const ContractGroup(id: 'cat_subs', name: 'Subscriptions', builtIn: true));
    if (!has('cat_other')) _categories.add(const ContractGroup(id: 'cat_other', name: 'General', builtIn: true));
    _reindexCategories();
  }

  Future<void> _hydrateNotes() async {
    final loaded = await _notesStore.loadAll();
    // Merge into existing in-memory contracts
    for (var i = 0; i < _contracts.length; i++) {
      final c = _contracts[i];
      final n = loaded[c.id];
      if (n != null) {
        _contracts[i] = c.copyWith(notes: n.text);
        _notesEditedAt[c.id] = n.updatedAt;
      }
    }
    notifyListeners();
  }

  Future<void> _hydrateProfile() async {
    final p = await _profileStore.load();
    if (p != null) {
      _profile = p;
      notifyListeners();
    }
  }

  // READ
  List<ContractGroup> get categories => List.unmodifiable(_categories);
  List<Contract> get contracts =>
      List.unmodifiable(_contracts.where((c) => !c.isDeleted));
  List<Contract> get trashedContracts =>
      List.unmodifiable(_contracts.where((c) => c.isDeleted));
  Contract? contractById(String id) {
    try {
      return _contracts.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }
  ContractGroup? categoryById(String id) => _categories.firstWhere(
        (c) => c.id == id,
        orElse: () => const ContractGroup(id: 'cat_other', name: 'General', builtIn: true),
      );

  List<Attachment> attachmentsFor(String contractId) =>
      List.unmodifiable(_attachments[contractId] ?? const []);

  bool get attachmentsGridPreferred => _attachmentsGridPreferred;
  void setAttachmentsGridPreferred(bool value) {
    if (_attachmentsGridPreferred == value) return;
    _attachmentsGridPreferred = value;
    notifyListeners();
    _persistSettings();
  }

  // User profile
  UserProfile get profile => _profile;
  Future<void> updateProfile(UserProfile p) async {
    _profile = p;
    notifyListeners();
    await _profileStore.save(p);
    // Log cloud-synced profile fields (no avatar bytes/paths)
    try {
      final ts = await DbService.instance.nextLamportTs();
      final fields = SyncRegistry.instance.toFields('profile', {
        'name': p.name,
        'email': p.email,
        'phone': p.phone,
        'locale': p.locale,
        'timezone': p.timezone,
        'currency': p.currency,
        'country': p.country,
      });
      await DbService.instance.logOp(
        entity: 'profile',
        entityId: 'me',
        op: 'put',
        rev: 0,
        ts: ts,
        fields: fields,
      );
      // Track last apply ts for LWW on receivers
      try {
        final db = await DbService.instance.db;
        await db.insert('settings', {'key': 'profile_ts', 'value': ts.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}
    } catch (_) {}
  }

  // Settings
  ThemeMode get themeMode => _themeMode;
  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    _persistSettings();
  }

  Future<void> _hydrateSettings() async {
    final s = await _settingsStore.load();
    // Cloud sync is a local-only toggle. Read from a dedicated local key to avoid being
    // overwritten by remote settings sync which omits this flag by design.
    try {
      final db = await DbService.instance.db;
      final rows = await db.query('settings', where: 'key = ?', whereArgs: ['cloud_sync_enabled'], limit: 1);
      if (rows.isNotEmpty) {
        final v = (rows.first['value'] as String?)?.toLowerCase();
        if (v != null) {
          _cloudSyncEnabled = (v == '1' || v == 'true');
        }
      }
    } catch (_) {}
    // Back-compat: if older JSON contained the flag, honor it once (will be persisted separately)
    final cloud = s['cloudSyncEnabled'] as bool?;
    final tm = s['themeMode'] as String?;
    final grid = s['attachmentsGridPreferred'] as bool?;
    final remEnabled = s['remindersEnabled'] as bool?;
    final push = s['pushEnabled'] as bool?;
    final banner = s['inAppBannerEnabled'] as bool?;
    final days = (s['reminderDays'] as List?)?.whereType<int>().toSet();
    final time = s['reminderTime'] as String?; // HH:MM
    final autoTrash = s['autoEmptyTrashEnabled'] as bool?;
    final autoDays = s['autoEmptyTrashDays'] as int?;
    final blk = s['blockScreenshots'] as bool?;
    final sh = s['allowShare'] as bool?;
    final dl = s['allowDownload'] as bool?;
    if (cloud != null) _cloudSyncEnabled = cloud;
    if (tm != null) {
      switch (tm) {
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        default:
          _themeMode = ThemeMode.system;
      }
    }
    if (grid != null) _attachmentsGridPreferred = grid;
    if (remEnabled != null) _remindersEnabled = remEnabled;
    if (push != null) _pushEnabled = push;
    if (banner != null) _inAppBannerEnabled = banner;
    if (days != null && days.isNotEmpty) _reminderDays = days;
    if (time != null && time.contains(':')) {
      final parts = time.split(':');
      final h = int.tryParse(parts[0]) ?? 9;
      final m = int.tryParse(parts[1]) ?? 0;
      _reminderTime = TimeOfDay(hour: h, minute: m);
    }
    if (autoTrash != null) _autoEmptyTrashEnabled = autoTrash;
    if (autoDays != null && autoDays > 0) _autoEmptyTrashDays = autoDays;
    if (blk != null) _blockScreenshots = blk;
    if (sh != null) _allowShare = sh;
    if (dl != null) _allowDownload = dl;
    // One-time in-session migration: stamp missing deletedAt so retention can apply
    final stamped = _stampDeletedAtIfMissing();
    if (stamped) {
      await _persistContracts();
    }
    notifyListeners();
    // Run an initial sweep after hydration
    _autoEmptyTrashSweep();
    // Schedule reminders with stable IDs after hydration, but never fail hydration
    try {
      await _rescheduleReminders();
    } catch (_) {}
  }

  Future<void> _persistSettings() async {
    final data = {
      // Do not include cloudSyncEnabled in the JSON blob. It is device-specific and
      // would be erased by remote pulls that omit it.
      'themeMode': switch (_themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
      'attachmentsGridPreferred': _attachmentsGridPreferred,
      'blockScreenshots': _blockScreenshots,
      'allowShare': _allowShare,
      'allowDownload': _allowDownload,
      'remindersEnabled': _remindersEnabled,
      'pushEnabled': _pushEnabled,
      'inAppBannerEnabled': _inAppBannerEnabled,
      'reminderDays': _reminderDays.toList()..sort(),
      'reminderTime': '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}',
      'autoEmptyTrashEnabled': _autoEmptyTrashEnabled,
      'autoEmptyTrashDays': _autoEmptyTrashDays,
    };
    await _settingsStore.save(data);
    // Persist local-only cloud flag separately
    try {
      final db = await DbService.instance.db;
      await db.insert('settings', {'key': 'cloud_sync_enabled', 'value': _cloudSyncEnabled ? '1' : '0'}, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
    // Cloud-sync selected user preferences (exclude device-specific flags)
    try {
      final ts = await DbService.instance.nextLamportTs();
    final cloud = SyncRegistry.instance.toFields('settings', data);
    await DbService.instance.logOp(
      entity: 'settings',
      entityId: 'me',
      op: 'put',
      rev: 0,
      ts: ts,
      fields: cloud,
    );
      // Track last settings ts for LWW
      try {
        final db = await DbService.instance.db;
        await db.insert('settings', {'key': 'settings_ts', 'value': ts.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}
    } catch (_) {}
  }

  // Persist current settings locally without logging a cloud sync op.
  // Used for local-only toggles (e.g., enabling sync) before the first
  // inbound hydration to avoid pushing default values that could override
  // server state.
  Future<void> _persistSettingsLocalOnly() async {
    final data = {
      // Do not include cloudSyncEnabled here either; store it under its own key.
      'themeMode': switch (_themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
      'attachmentsGridPreferred': _attachmentsGridPreferred,
      'blockScreenshots': _blockScreenshots,
      'allowShare': _allowShare,
      'allowDownload': _allowDownload,
      'remindersEnabled': _remindersEnabled,
      'pushEnabled': _pushEnabled,
      'inAppBannerEnabled': _inAppBannerEnabled,
      'reminderDays': _reminderDays.toList()..sort(),
      'reminderTime': '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}',
      'autoEmptyTrashEnabled': _autoEmptyTrashEnabled,
      'autoEmptyTrashDays': _autoEmptyTrashDays,
    };
    await _settingsStore.save(data);
    try {
      final db = await DbService.instance.db;
      await db.insert('settings', {'key': 'cloud_sync_enabled', 'value': _cloudSyncEnabled ? '1' : '0'}, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
  }

  // Cloud sync getter/setter
  bool get cloudSyncEnabled => _cloudSyncEnabled;
  void setCloudSyncEnabled(bool v) {
    if (_cloudSyncEnabled == v) return;
    _cloudSyncEnabled = v;
    notifyListeners();
    // Important: avoid logging a cloud settings op here to prevent
    // pushing default local values before the first hydration pull.
    // Persist locally only so the toggle survives restarts.
    _persistSettingsLocalOnly();
    // Start/stop sync loop accordingly
    if (v) {
      // Only start if signed in; otherwise wait until auth listener sees a user
      if (fb.FirebaseAuth.instance.currentUser != null) {
        _ensureSyncService();
        _sync?.resume();
      }
    } else {
      _sync?.pause();
    }
  }

  // Sync status
  bool get isSyncing => _syncing;
  int? get lastSyncTs => _lastSyncTs;
  String? get lastSyncError => _lastSyncError;

  // Quick check for pending local operations after the current cursor.
  // Used by UI to color the sync status tag.
  Future<bool> hasPendingLocalOps() async {
    try {
      final since = await DbService.instance.getPushCursorTs();
      final rows = await DbService.instance.fetchOplogSince(since, limit: 1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureSyncService() async {
    if (!_cloudSyncEnabled) {
      // Do not create or run a sync service when cloud sync is disabled
      _sync = null;
      return;
    }
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Do not create a no-op service; wait for sign-in
      _sync = null;
      return;
    }
    if (_sync is FirebaseSyncService) return;
    _sync = FirebaseSyncService();
    // After each background tick, refresh in-memory state so UI updates
    _sync!.setOnAfterSync(() {
      // Fire-and-forget rehydrate; ignore failures to keep ticks cheap
      Future.microtask(() async {
        try {
          await _hydrateContracts();
          await _hydrateNotes();
          await _hydrateSettings();
          await _hydrateProfile();
          for (final c in _contracts) {
            _attachments[c.id] = await _attachmentsRepo.list(c.id);
          }
          _dedupeCategoriesByName();
        } catch (_) {}
      });
    });
  }

  Future<void> syncNow() async {
    if (_isRestoring) return; // suppress manual sync during restore
    if (!_cloudSyncEnabled) {
      // Respect disabled state: ignore manual sync requests when cloud sync is off
      return;
    }
    if (_cloudSyncEnabled) {
      // Guard: require DEK for cloud sync to avoid undecryptable ops
      if (!_hasCloudDek) {
        _lastSyncError = 'Cloud key missing. Finish cloud key setup.';
        notifyListeners();
        return;
      }
    }
    if (_sync == null) {
      await _ensureSyncService();
    }
    if (_sync == null) return;
    _syncing = true;
    _lastSyncError = null;
    notifyListeners();
    try {
      await _sync!.syncOnce();
      _lastSyncTs = DateTime.now().millisecondsSinceEpoch;
      // Rehydrate in-memory models so UI reflects newly synced data immediately
      try {
        await _hydrateContracts();
        await _hydrateNotes();
        await _hydrateSettings();
        await _hydrateProfile();
        // Refresh attachment lists for all known contracts
        for (final c in _contracts) {
          _attachments[c.id] = await _attachmentsRepo.list(c.id);
        }
      } catch (_) {}
      // Opportunistically write an encrypted snapshot for faster first-run on other devices
      // Fire-and-forget to avoid blocking UI
      Future.microtask(() async {
        final user = fb.FirebaseAuth.instance.currentUser;
        if (user != null && _cloudSyncEnabled && _hasCloudDek) {
          await SnapshotService.instance.maybeWriteSnapshot();
        }
      });
    } catch (e) {
      _lastSyncError = e.toString();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  // Cloud key (DEK) presence wiring
  Future<void> refreshCloudDekAvailable() async {
    try {
      final dek = await KeyringService.instance.getLocalDek();
      _hasCloudDek = dek != null;
    } catch (_) {
      _hasCloudDek = false;
    }
    notifyListeners();
  }

  void setCloudDekAvailable(bool v) {
    if (_hasCloudDek == v) return;
    _hasCloudDek = v;
    notifyListeners();
  }

  void _bindAuthListener() {
    // React to sign-in/out and reconfigure sync service accordingly
    _authSub?.cancel();
    _authSub = fb.FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!_cloudSyncEnabled) {
        // If sync disabled, ensure no service is running
        try { await _sync?.pause(); } catch (_) {}
        _sync = null;
        return;
      }
      if (user == null) {
        // Signed out: pause and drop service; do not create LocalSyncService
        try { await _sync?.pause(); } catch (_) {}
        _sync = null;
        notifyListeners();
        return;
      }
      // Signed in: ensure Firebase service is running
      if (_sync is! FirebaseSyncService) {
        try { await _sync?.pause(); } catch (_) {}
        _sync = FirebaseSyncService();
        try { await _sync!.start(); } catch (_) {}
        notifyListeners();
      }
      // Immediately trigger a sync when signed in and a DEK is present
      if (_hasCloudDek) {
        // fire-and-forget; UI will reflect status via listeners
        Future.microtask(() => syncNow());
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _sync?.pause();
    super.dispose();
  }

  // Reminders getters/setters
  bool get remindersEnabled => _remindersEnabled;
  bool get pushEnabled => _pushEnabled;
  bool get inAppBannerEnabled => _inAppBannerEnabled;
  Set<int> get reminderDays => _reminderDays;
  TimeOfDay get reminderTime => _reminderTime;

  void setRemindersEnabled(bool v) {
    if (_remindersEnabled == v) return;
    _remindersEnabled = v;
    notifyListeners();
    _persistSettings();
    _rescheduleReminders();
  }

  void setPushEnabled(bool v) {
    if (_pushEnabled == v) return;
    _pushEnabled = v;
    notifyListeners();
    _persistSettings();
    _rescheduleReminders();
  }

  void setInAppBannerEnabled(bool v) {
    if (_inAppBannerEnabled == v) return;
    _inAppBannerEnabled = v;
    notifyListeners();
    _persistSettings();
  }

  void toggleReminderDay(int day) {
    if (_reminderDays.contains(day)) {
      _reminderDays.remove(day);
    } else {
      _reminderDays.add(day);
    }
    notifyListeners();
    _persistSettings();
    _rescheduleReminders();
  }

  void setReminderTime(TimeOfDay t) {
    _reminderTime = t;
    notifyListeners();
    _persistSettings();
    _rescheduleReminders();
  }

  // Privacy controls getters/setters
  bool get blockScreenshots => _blockScreenshots;
  bool get allowShare => _allowShare;
  bool get allowDownload => _allowDownload;
  // Biometric controls removed

  void setBlockScreenshots(bool v) { _blockScreenshots = v; notifyListeners(); _persistSettings(); }
  void setAllowShare(bool v) { _allowShare = v; notifyListeners(); _persistSettings(); }
  void setAllowDownload(bool v) { _allowDownload = v; notifyListeners(); _persistSettings(); }
  // Removed setters for biometric controls

  // Export all data into a zip inside app documents
  Future<String> exportAll() async {
    // Legacy export removed. Use encrypted DB export instead.
    return await exportEncryptedBackupToDownloads('local-backup');
  }

  // Wipe local data
  Future<void> wipeLocalData() async {
    final dir = await AppDirs.supportDir();
    for (final name in ['contracts.enc','contracts.json','notes.enc','notes.json','profile.enc','profile.json','settings.enc','settings.json','emk.json']) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) { try { await f.delete(); } catch (_) {} }
    }
    final attachmentsDir = Directory('${dir.path}/attachments');
    if (await attachmentsDir.exists()) { try { await attachmentsDir.delete(recursive: true); } catch (_) {} }
    _attachments.clear();
    _notesEditedAt.clear();
    _contracts.clear();
    _attachmentsGridPreferred = false;
    _themeMode = ThemeMode.system;
    _remindersEnabled = true;
    _pushEnabled = true;
    _inAppBannerEnabled = true;
    _reminderDays = {1,7,14,30};
    _reminderTime = const TimeOfDay(hour: 9, minute: 0);
    _blockScreenshots = true;
    _allowShare = true;
    _allowDownload = true;
    // Biometric settings removed
    notifyListeners();
    // Crypto key wipe not required with DB-backed encryption
  }

  // Reset local contracts to the built-in demo dataset (for development/testing)
  Future<void> resetToDemoData() async {
    // Clear all in-memory lists and persist empty state
    _attachments.clear();
    _notesEditedAt.clear();
    _contracts.clear();
    notifyListeners();
    await _persistContracts();
    await _rescheduleReminders();
  }

  // Import a previously exported zip and replace local data
  Future<bool> importFromZip(String zipPath, {required String passphrase}) async {
    // Disabled for DB-backed storage; implement DB backup/restore later
    return false;
  }

  Future<String> exportEncryptedBackupToDownloads(String passphrase) async {
    if (passphrase.length < 8) {
      throw ArgumentError('Passphrase must be at least 8 characters');
    }
    // Build logical backup (contracts, categories, notes, attachments only)
    final db = await DbService.instance.db;
    final cats = await db.query('contract_groups');
    final cons = await db.query('contracts');
    final notes = await db.query('notes');
    final atts = await db.query('attachments');
    final payload = <String, dynamic>{
      'format': 'logical-v1',
      'exportedAt': DateTime.now().toIso8601String(),
      'categories': cats
          .map((r) => {
                'id': r['id'],
                'name': r['name'],
                'built_in': r['built_in'],
              })
          .toList(),
      'contracts': cons.toList(),
      'notes': notes.toList(),
      'attachments': atts.map((r) {
        final m = Map<String, Object?>.from(r);
        final data = m.remove('data') as Uint8List?;
        m['data_b64'] = data != null ? base64Encode(data) : null;
        return m;
      }).toList(),
    };
    final clearBytes = utf8.encode(jsonEncode(payload));
    final rng = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(16, (_) => rng.nextInt(256)));
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 150000, bits: 256);
    final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    final keyBytes = await key.extractBytes();
    final algo = AesGcm.with256bits();
    final nonce = Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));
    final sb = await algo.encrypt(clearBytes, secretKey: SecretKey(keyBytes), nonce: nonce);
    final header = {
      'v': 2,
      'alg': 'aes-gcm-256',
      'kdf': 'pbkdf2-hmac-sha256',
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
    };
    final headerBytes = utf8.encode(jsonEncode(header));
    final len = ByteData(4)..setUint32(0, headerBytes.length, Endian.big);
    final out = <int>[
      ...len.buffer.asUint8List(),
      ...headerBytes,
      ...sb.cipherText,
      ...sb.mac.bytes,
    ];
    String outPath;
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      outPath = '${downloads.path}/contract_manager_backup_${DateTime.now().millisecondsSinceEpoch}.enc';
      try {
        await File(outPath).writeAsBytes(out, flush: true);
      } catch (_) {
        final dir = await AppDirs.supportDir();
        outPath = '${dir.path}/contract_manager_backup_${DateTime.now().millisecondsSinceEpoch}.enc';
        await File(outPath).writeAsBytes(out, flush: true);
      }
    } else {
      final dir = await AppDirs.supportDir();
      outPath = '${dir.path}/contract_manager_backup_${DateTime.now().millisecondsSinceEpoch}.enc';
      await File(outPath).writeAsBytes(out, flush: true);
    }
    return outPath;
  }

  Future<bool> importEncryptedBackupFromPath(String encPath, String passphrase) async {
    try {
      if (passphrase.length < 8) {
        throw ArgumentError('Passphrase must be at least 8 characters');
      }
      final f = File(encPath);
      if (!await f.exists()) return false;
      final bytes = await f.readAsBytes();
      if (bytes.length < 4) return false;
      final hlen = ByteData.sublistView(Uint8List.fromList(bytes.take(4).toList())).getUint32(0, Endian.big);
      final headerJson = utf8.decode(bytes.sublist(4, 4 + hlen));
      final header = jsonDecode(headerJson) as Map<String, dynamic>;
      final hv = (header['v'] as num?)?.toInt() ?? 1;
      if (hv < 2) {
        throw const FormatException('Legacy backup format not supported');
      }
      final salt = base64Decode(header['salt'] as String);
      final nonce = base64Decode(header['nonce'] as String);
      final cipherText = bytes.sublist(4 + hlen, bytes.length - 16);
      final mac = Mac(bytes.sublist(bytes.length - 16));
      final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 150000, bits: 256);
      final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
      final keyBytes = await key.extractBytes();
      final algo = AesGcm.with256bits();
      final clear = await algo.decrypt(SecretBox(cipherText, nonce: nonce, mac: mac), secretKey: SecretKey(keyBytes));
      // Parse logical payload
      final obj = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      if (obj['format'] != 'logical-v1') {
        throw const FormatException('Unsupported backup content');
      }
      final db = await DbService.instance.db;
      _isRestoring = true;
      try { await _sync?.pause(); } catch (_) {}
      // Snapshot existing state before reconcile
      final existingCatsRows = await db.query('contract_groups');
      final existingConsRows = await db.query('contracts');
      final existingNotesRows = await db.query('notes');
      final existingAttsRows = await db.query('attachments');
      final existingCats = {for (final r in existingCatsRows) r['id'] as String: r};
      final existingCons = {for (final r in existingConsRows) r['id'] as String: r};
      final existingNotes = {for (final r in existingNotesRows) r['contract_id'] as String: r};
      final existingAtts = {for (final r in existingAttsRows) r['id'] as String: r};

      await db.transaction((txn) async {
        // Reconcile categories (upsert restored, tombstone missing)
        final cats = (obj['categories'] as List);
        final restoredCatIds = <String>{};
        for (final r in cats) {
          final mr = Map<String, dynamic>.from(r as Map);
          final id = mr['id'] as String;
          restoredCatIds.add(id);
          final prev = existingCats[id];
          final prevRev = (prev?['rev'] as int?) ?? 0;
          final ts = await DbService.instance.nextLamportTs();
          final rev = prevRev + 1;
          final row = {
            'id': id,
            'name': mr['name'],
            'built_in': (mr['built_in'] as num?)?.toInt() ?? 0,
            'deleted': 0,
            'rev': rev,
            'updated_at': ts,
          };
          await txn.insert('contract_groups', row, conflictAlgorithm: ConflictAlgorithm.replace);
          await DbService.instance.logOp(entity: 'category', entityId: id, op: 'put', rev: rev, ts: ts, fields: {'name': mr['name'], 'built_in': (mr['built_in'] as num?)?.toInt() ?? 0});
        }
        for (final entry in existingCats.entries) {
          if (!restoredCatIds.contains(entry.key) && ((entry.value['deleted'] as int?) ?? 0) == 0) {
          final ts = await DbService.instance.nextLamportTsTx(txn);
          final rev = ((entry.value['rev'] as int?) ?? 0) + 1;
          await txn.update('contract_groups', {'deleted': 1, 'rev': rev, 'updated_at': ts}, where: 'id = ?', whereArgs: [entry.key]);
          await DbService.instance.logOpTx(txn, entity: 'category', entityId: entry.key, op: 'delete', rev: rev, ts: ts, fields: null);
        }
      }

        // Reconcile contracts
        final cons = (obj['contracts'] as List);
        final restoredConIds = <String>{};
        for (final r in cons) {
          final m = Map<String, Object?>.from(Map<String, dynamic>.from(r as Map));
          final id = m['id'] as String;
          restoredConIds.add(id);
          final prev = existingCons[id];
          final prevRev = (prev?['rev'] as int?) ?? 0;
          final baseRev = (m['rev'] as int?) ?? 0;
          final ts = await DbService.instance.nextLamportTsTx(txn, m['updated_at'] as int?);
          final rev = (baseRev > prevRev ? baseRev : prevRev) + 1;
          m['rev'] = rev;
          m['updated_at'] = ts;
          await txn.insert('contracts', m, conflictAlgorithm: ConflictAlgorithm.replace);
          await DbService.instance.logOpTx(txn, entity: 'contract', entityId: id, op: ((m['is_deleted'] as int?) ?? 0) == 1 ? 'delete' : 'put', rev: rev, ts: ts, fields: SyncRegistry.instance.toFields('contract', m));
        }
        for (final entry in existingCons.entries) {
          if (!restoredConIds.contains(entry.key) && ((entry.value['is_deleted'] as int?) ?? 0) == 0) {
            final ts = await DbService.instance.nextLamportTsTx(txn);
            final rev = ((entry.value['rev'] as int?) ?? 0) + 1;
            await txn.update('contracts', {'is_deleted': 1, 'deleted_at': ts, 'rev': rev, 'updated_at': ts}, where: 'id = ?', whereArgs: [entry.key]);
            await DbService.instance.logOpTx(txn, entity: 'contract', entityId: entry.key, op: 'delete', rev: rev, ts: ts, fields: null);
          }
        }

        // Reconcile notes
        final notes = (obj['notes'] as List);
        final restoredNoteIds = <String>{};
        for (final r in notes) {
          final m = Map<String, Object?>.from(Map<String, dynamic>.from(r as Map));
          final id = m['contract_id'] as String;
          restoredNoteIds.add(id);
          final ts = await DbService.instance.nextLamportTsTx(txn, m['updated_at'] as int?);
          m['updated_at'] = ts;
          await txn.insert('notes', m, conflictAlgorithm: ConflictAlgorithm.replace);
          await DbService.instance.logOpTx(txn, entity: 'note', entityId: id, op: 'put', rev: 0, ts: ts, fields: SyncRegistry.instance.toFields('note', {'text': m['text']}));
        }
        for (final entry in existingNotes.entries) {
          if (!restoredNoteIds.contains(entry.key)) {
            await txn.delete('notes', where: 'contract_id = ?', whereArgs: [entry.key]);
            final ts = await DbService.instance.nextLamportTsTx(txn);
            await DbService.instance.logOpTx(txn, entity: 'note', entityId: entry.key, op: 'delete', rev: 0, ts: ts, fields: null);
          }
        }

        // Reconcile attachments
        final atts = (obj['attachments'] as List);
        final restoredAttIds = <String>{};
        for (final r in atts) {
          final m = Map<String, Object?>.from(Map<String, dynamic>.from(r as Map));
          final id = m['id'] as String;
          restoredAttIds.add(id);
          final b64 = m.remove('data_b64') as String?;
          String? blobHash;
          if (b64 != null) {
            final bytes = base64Decode(b64);
            final digest = await Sha256().hash(bytes);
            blobHash = _hexFromBytes(digest.bytes);
            final existing = await txn.query('blobs', where: 'hash = ?', whereArgs: [blobHash], limit: 1);
            if (existing.isEmpty) {
              await txn.insert('blobs', {'hash': blobHash, 'data': Uint8List.fromList(bytes), 'refcount': 1});
            } else {
              final rc = ((existing.first['refcount'] as int?) ?? 0) + 1;
              await txn.update('blobs', {'refcount': rc}, where: 'hash = ?', whereArgs: [blobHash]);
            }
            m['data'] = Uint8List(0);
          }
          if (blobHash != null) m['blob_hash'] = blobHash;
          final prev = existingAtts[id];
          final prevRev = (prev?['rev'] as int?) ?? 0;
          final baseRev = (m['rev'] as int?) ?? 0;
          final ts = await DbService.instance.nextLamportTsTx(txn, m['updated_at'] as int?);
          final rev = (baseRev > prevRev ? baseRev : prevRev) + 1;
          m['rev'] = rev;
          m['updated_at'] = ts;
          await txn.insert('attachments', m, conflictAlgorithm: ConflictAlgorithm.replace);
          await DbService.instance.logOpTx(txn, entity: 'attachment', entityId: id, op: ((m['deleted'] as int?) ?? 0) == 1 ? 'delete' : 'put', rev: rev, ts: ts, fields: SyncRegistry.instance.toFields('attachment', {'contract_id': m['contract_id'], 'name': m['name'], 'type': m['type'], 'blob_hash': m['blob_hash']}));
        }
        for (final entry in existingAtts.entries) {
          if (!restoredAttIds.contains(entry.key) && ((entry.value['deleted'] as int?) ?? 0) == 0) {
            final ts = await DbService.instance.nextLamportTsTx(txn);
            final rev = ((entry.value['rev'] as int?) ?? 0) + 1;
            final blobHash = entry.value['blob_hash'] as String?;
            await txn.update('attachments', {'deleted': 1, 'rev': rev, 'updated_at': ts}, where: 'id = ?', whereArgs: [entry.key]);
            await txn.delete('thumbs', where: 'attachment_id = ?', whereArgs: [entry.key]);
            if (blobHash != null && blobHash.isNotEmpty) {
              final b = await txn.query('blobs', where: 'hash = ?', whereArgs: [blobHash], limit: 1);
              if (b.isNotEmpty) {
                final rc = ((b.first['refcount'] as int?) ?? 1) - 1;
                if (rc <= 0) {
                  await txn.delete('blobs', where: 'hash = ?', whereArgs: [blobHash]);
                } else {
                  await txn.update('blobs', {'refcount': rc}, where: 'hash = ?', whereArgs: [blobHash]);
                }
              }
            }
            await DbService.instance.logOpTx(txn, entity: 'attachment', entityId: entry.key, op: 'delete', rev: rev, ts: ts, fields: null);
          }
        }
      });
      await rehydrateAll();
      // After restore, perform a one-shot sync to publish changes
      try { await syncNow(); } catch (_) {}
      try { await _sync?.resume(); } catch (_) {}
      _isRestoring = false;
      return true;
    } on SecretBoxAuthenticationError {
      throw WrongPassphraseError();
    } catch (_) {
      return false;
    }
  }

  Future<void> _rescheduleReminders() async {
    if (!_remindersEnabled || !_pushEnabled) {
      // If push reminders are disabled, cancel all
      for (final c in contracts) {
        await NotificationService.instance.cancelForContract(c.id);
      }
      return;
    }
    final days = Set<int>.from(_reminderDays);
    tz.TZDateTime timeFor(DateTime day) {
      return tz.TZDateTime(
        tz.local,
        day.year,
        day.month,
        day.day,
        _reminderTime.hour,
        _reminderTime.minute,
      );
    }
    for (final c in contracts) {
      await NotificationService.instance.cancelForContract(c.id);
      await NotificationService.instance.scheduleForContract(
        contract: c,
        days: days,
        timeForEndDate: timeFor,
      );
    }
  }
  Future<void> setProfileAvatarFromPath(String sourcePath) async {
    final file = File(sourcePath);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      await updateProfile(_profile.copyWith(photoBytes: Uint8List.fromList(bytes)));
    }
  }

  DateTime? lastNoteEditedAt(String contractId) => _notesEditedAt[contractId];

  Future<Uint8List> readAttachmentBytes(String contractId, Attachment a) async {
    try {
      return await _attachmentsRepo.readDecrypted(contractId, a);
    } catch (_) {
      // Try just-in-time fetch from Firebase Storage if blob exists remotely.
      if (!cloudSyncEnabled) rethrow;
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) rethrow;
      try {
        final db = await DbService.instance.db;
        final rows = await db.query('attachments', columns: ['blob_hash'], where: 'id = ?', whereArgs: [a.id], limit: 1);
        if (rows.isEmpty) rethrow;
        final bh = rows.first['blob_hash'] as String?;
        if (bh == null || bh.isEmpty) rethrow;
        // Download if missing locally
        final existing = await db.query('blobs', where: 'hash = ?', whereArgs: [bh], limit: 1);
        if (existing.isEmpty) {
          final ref = FirebaseStorage.instance.ref('users/${user.uid}/blobs/$bh');
          final data = await ref.getData(25 * 1024 * 1024); // 25 MB cap
          if (data != null) {
            try {
              final dek = await KeyringService.instance.getLocalDek();
              if (dek == null) throw StateError('Cloud DEK unavailable');
              final plain = await BlobCrypto.decrypt(data, dek);
              await db.insert('blobs', {'hash': bh, 'data': plain, 'refcount': 1}, conflictAlgorithm: ConflictAlgorithm.replace);
            } catch (e) {
              rethrow;
            }
          }
        }
        return await _attachmentsRepo.readDecrypted(contractId, a);
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<Uint8List?> cachedPdfThumb(String contractId, Attachment a, {required int width}) async {
    return _attachmentsRepo.loadCachedThumb(contractId, a.id, width);
  }

  Future<Uint8List> getOrCreatePdfThumb(String contractId, Attachment a, {required int width}) async {
    final data = await readAttachmentBytes(contractId, a);
    return _attachmentsRepo.getOrCreatePdfThumb(contractId, a, data, width);
  }

  Future<void> warmThumbnails(String contractId, {required double devicePixelRatio}) async {
    // Generate common thumbnail sizes scaled by device pixel ratio
    final sizes = <int>{
      (80 * devicePixelRatio).round(),
      (120 * devicePixelRatio).round(),
      (160 * devicePixelRatio).round(),
    }..removeWhere((w) => w <= 0);
    final list = attachmentsFor(contractId);
    for (final a in list) {
      if (a.type == AttachmentType.pdf) {
        for (final w in sizes) {
          // Fire and forget warming
          Future.microtask(() => getOrCreatePdfThumb(contractId, a, width: w));
        }
      }
    }
  }

  // MUTATE
  void addContract(Contract c) {
    _contracts.add(c);
    notifyListeners();
    _persistContracts();
    _rescheduleReminders();
  }

  void updateContract(Contract c) {
    final i = _contracts.indexWhere((e) => e.id == c.id);
    if (i != -1) {
      final prev = _contracts[i];
      _contracts[i] = c;
      // Persist notes if they changed
      if ((prev.notes ?? '') != (c.notes ?? '')) {
        final now = DateTime.now();
        _notesEditedAt[c.id] = now;
        // Fire-and-forget persistence to disk
        Future.microtask(() => _notesStore.saveNote(c.id, c.notes ?? '', now));
      }
      notifyListeners();
      _persistContracts();
      // Reschedule if end date or active status changed
      if (prev.endDate != c.endDate || prev.isActive != c.isActive || prev.isDeleted != c.isDeleted) {
        _rescheduleReminders();
      }
    }
  }

  // Safer, awaitable variants with error reporting for UI
  Future<bool> tryAddContract(Contract c) async {
    _contracts.add(c);
    notifyListeners();
    try {
      await _persistContracts();
      // Do not treat reminder scheduling failures as persistence failures
      try { await _rescheduleReminders(); } catch (_) {}
      return true;
    } catch (_) {
      // Revert on failure
      _contracts.removeWhere((e) => e.id == c.id);
      notifyListeners();
      return false;
    }
  }

  Future<bool> tryUpdateContract(Contract c) async {
    final i = _contracts.indexWhere((e) => e.id == c.id);
    if (i == -1) return false;
    final prev = _contracts[i];
    _contracts[i] = c;
    final notesChanged = (prev.notes ?? '') != (c.notes ?? '');
    if (notesChanged) {
      final now = DateTime.now();
      _notesEditedAt[c.id] = now;
    }
    notifyListeners();
    try {
      if (notesChanged) {
        final now = _notesEditedAt[c.id] ?? DateTime.now();
        await _notesStore.saveNote(c.id, c.notes ?? '', now);
      }
      await _persistContracts();
      if (prev.endDate != c.endDate || prev.isActive != c.isActive || prev.isDeleted != c.isDeleted) {
        // Do not propagate scheduling errors to the save flow
        try { await _rescheduleReminders(); } catch (_) {}
      }
      return true;
    } catch (_) {
      // Revert
      _contracts[i] = prev;
      if (notesChanged) {
        _notesEditedAt[c.id] = _notesEditedAt[c.id] ?? DateTime.now();
      }
      notifyListeners();
      return false;
    }
  }

  Future<bool> trySaveNote(String contractId, String text) async {
    final i = _contracts.indexWhere((e) => e.id == contractId);
    if (i == -1) return false;
    final prev = _contracts[i];
    final updated = prev.copyWith(notes: text);
    _contracts[i] = updated;
    final now = DateTime.now();
    _notesEditedAt[contractId] = now;
    notifyListeners();
    try {
      await _notesStore.saveNote(contractId, text, now);
      await _persistContracts();
      return true;
    } catch (_) {
      _contracts[i] = prev;
      notifyListeners();
      return false;
    }
  }

  void deleteContract(String id) {
    final i = _contracts.indexWhere((e) => e.id == id);
    if (i != -1) {
      final c = _contracts[i];
      _contracts[i] = c.copyWith(isActive: false, isDeleted: true, deletedAt: DateTime.now());
      notifyListeners();
      _persistContracts();
    }
  }

  void purgeContract(String id) {
    // Hard-delete locally and emit a 'purge' op so other devices delete too
    Future.microtask(() async {
      try {
        final db = await DbService.instance.db;
        await db.transaction((txn) async {
          // Emit purge op with rev+1 if exists
          final rows = await txn.query('contracts', where: 'id = ?', whereArgs: [id], limit: 1);
          int prevRev = 0;
          if (rows.isNotEmpty) {
            prevRev = (rows.first['rev'] as int?) ?? 0;
          }
          int rev = prevRev + 1;
          final ts = await DbService.instance.nextLamportTsTx(txn);
          await DbService.instance.logOpTx(txn, entity: 'contract', entityId: id, op: 'purge', rev: rev, ts: ts, fields: null);
          // Delete attachments and blobs
          final atts = await txn.query('attachments', where: 'contract_id = ?', whereArgs: [id]);
          for (final a in atts) {
            final bh = a['blob_hash'] as String?;
            await txn.delete('thumbs', where: 'attachment_id = ?', whereArgs: [a['id']]);
            await txn.delete('attachments', where: 'id = ?', whereArgs: [a['id']]);
            if (bh != null && bh.isNotEmpty) {
              final b = await txn.query('blobs', where: 'hash = ?', whereArgs: [bh], limit: 1);
              if (b.isNotEmpty) {
                final rc = ((b.first['refcount'] as int?) ?? 1) - 1;
                if (rc <= 0) {
                  await txn.delete('blobs', where: 'hash = ?', whereArgs: [bh]);
                } else {
                  await txn.update('blobs', {'refcount': rc}, where: 'hash = ?', whereArgs: [bh]);
                }
              }
            }
          }
          await txn.delete('notes', where: 'contract_id = ?', whereArgs: [id]);
          await txn.delete('contracts', where: 'id = ?', whereArgs: [id]);
        });
      } catch (_) {}
    });
    _contracts.removeWhere((e) => e.id == id);
    _attachments.remove(id);
    _notesEditedAt.remove(id);
    notifyListeners();
    NotificationService.instance.cancelForContract(id);
  }

  // Auto-empty trash
  bool _autoEmptyTrashEnabled = false;
  int _autoEmptyTrashDays = 30;

  bool get autoEmptyTrashEnabled => _autoEmptyTrashEnabled;
  int get autoEmptyTrashDays => _autoEmptyTrashDays;
  void setAutoEmptyTrashEnabled(bool v) {
    if (_autoEmptyTrashEnabled == v) return;
    _autoEmptyTrashEnabled = v;
    notifyListeners();
    _persistSettings();
    _autoEmptyTrashSweep();
  }
  void setAutoEmptyTrashDays(int days) {
    if (days <= 0 || _autoEmptyTrashDays == days) return;
    _autoEmptyTrashDays = days;
    notifyListeners();
    _persistSettings();
    _autoEmptyTrashSweep();
  }
  void _autoEmptyTrashSweep() {
    if (!_autoEmptyTrashEnabled) return;
    final now = DateTime.now();
    final threshold = Duration(days: _autoEmptyTrashDays);
    final toPurge = trashedContracts
        .where((c) => c.deletedAt != null && now.difference(c.deletedAt!).compareTo(threshold) >= 0)
        .map((c) => c.id)
        .toList();
    for (final id in toPurge) {
      purgeContract(id);
    }
  }

  bool _stampDeletedAtIfMissing() {
    var changed = false;
    for (var i = 0; i < _contracts.length; i++) {
      final c = _contracts[i];
      if (c.isDeleted && c.deletedAt == null) {
        _contracts[i] = c.copyWith(deletedAt: DateTime.now());
        changed = true;
      }
    }
    return changed;
  }

  void purgeAll() {
    final ids = _contracts.where((e) => e.isDeleted).map((e) => e.id).toList();
    for (final id in ids) {
      purgeContract(id);
    }
  }

  String addCategory(String name) {
    final id = 'cat_${DateTime.now().microsecondsSinceEpoch}';
    // Insert before 'Other' if present, else at end
    final otherIndex = _categories.indexWhere((c) => c.id == 'cat_other');
    final insertAt = otherIndex == -1 ? _categories.length : otherIndex;
    _categories.insert(
      insertAt,
      ContractGroup(id: id, name: name, builtIn: false, orderIndex: insertAt),
    );
    _reindexCategories();
    notifyListeners();
    _persistContracts();
    return id;
  }

  void renameCategory(String id, String newName) {
    final i = _categories.indexWhere((c) => c.id == id);
    if (i != -1) {
      final old = _categories[i];
      _categories[i] = ContractGroup(
        id: old.id,
        name: newName,
        builtIn: old.builtIn,
        orderIndex: old.orderIndex,
        iconKey: old.iconKey,
      );
      notifyListeners();
      _persistContracts();
    }
  }

  int deleteCategory(String id) {
    // Default behavior: move to 'Other' if present
    final fallback = _categories.any((c) => c.id == 'cat_other')
        ? 'cat_other'
        : (_categories.firstWhere((c) => c.id != id, orElse: () => _categories.first).id);
    return deleteCategoryWithFallback(id, fallback);
  }

  int deleteCategoryWithFallback(String id, String fallbackCategoryId) {
    if (!_categories.any((c) => c.id == id)) return 0;
    if (!_categories.any((c) => c.id == fallbackCategoryId)) return 0;
    final moved = _contracts.where((c) => c.categoryId == id).toList();
    for (final c in moved) {
      updateContract(c.copyWith(categoryId: fallbackCategoryId));
    }
    _categories.removeWhere((c) => c.id == id);
    // Persist tombstone to DB + sync
    try { _contractsStore.tombstoneCategory(id); } catch (_) {}
    _reindexCategories();
    notifyListeners();
    _persistContracts();
    return moved.length;
  }

  void updateCategoryMeta(String id, {String? name, String? iconKey}) {
    final i = _categories.indexWhere((c) => c.id == id);
    if (i == -1) return;
    final old = _categories[i];
    _categories[i] = ContractGroup(
      id: old.id,
      name: name ?? old.name,
      builtIn: old.builtIn,
      orderIndex: old.orderIndex,
      iconKey: iconKey ?? old.iconKey,
    );
    notifyListeners();
    _persistContracts();
  }

  void reorderCategory(String id, int newIndex) {
    final i = _categories.indexWhere((c) => c.id == id);
    if (i == -1) return;
    // Pin 'Other' category at the end; do not allow moving it
    final lastIndex = _categories.length - 1;
    if (id == 'cat_other') {
      if (i == lastIndex) return; // already last
      final item = _categories.removeAt(i);
      _categories.insert(lastIndex, item);
      _reindexCategories();
      notifyListeners();
      _persistContracts();
      return;
    }
    if (newIndex < 0) newIndex = 0;
    // If 'Other' is last, keep it last by clamping destination
    if (_categories.isNotEmpty && _categories[lastIndex].id == 'cat_other' && newIndex >= lastIndex) {
      newIndex = (lastIndex - 1).clamp(0, lastIndex);
    } else if (newIndex >= _categories.length) {
      newIndex = _categories.length - 1;
    }
    final item = _categories.removeAt(i);
    _categories.insert(newIndex, item);
    _reindexCategories();
    notifyListeners();
    _persistContracts();
  }

  void _reindexCategories() {
    for (var i = 0; i < _categories.length; i++) {
      final c = _categories[i];
      _categories[i] = ContractGroup(
        id: c.id,
        name: c.name,
        builtIn: c.builtIn,
        orderIndex: i,
        iconKey: c.iconKey,
      );
    }
  }

  void _dedupeCategoriesByName() {
    final byName = <String, String>{};
    final losers = <String, String>{};
    for (final c in _categories) {
      final n = c.name.trim().toLowerCase();
      final w = byName[n];
      if (w == null) {
        byName[n] = c.id;
      } else if (w != c.id) {
        losers[c.id] = w;
      }
    }
    if (losers.isEmpty) return;
    losers.forEach((loserId, winnerId) {
      for (var i = 0; i < _contracts.length; i++) {
        final con = _contracts[i];
        if (con.categoryId == loserId) {
          _contracts[i] = con.copyWith(categoryId: winnerId);
        }
      }
      _categories.removeWhere((c) => c.id == loserId);
      try { _contractsStore.tombstoneCategory(loserId); } catch (_) {}
    });
    _reindexCategories();
    notifyListeners();
    _persistContracts();
  }

  Future<void> _persistContracts() async {
    if (_isLoading || _isRestoring) return;
    if (_saveInProgress) {
      _saveAgain = true;
      return;
    }
    _saveInProgress = true;
    try {
      do {
        _saveAgain = false;
        _lastSave = _contractsStore.save(_categories, _contracts);
        await _lastSave;
      } while (_saveAgain);
    } finally {
      _saveInProgress = false;
    }
  }

  Future<void> flushPendingSaves() async {
    try {
      if (_saveInProgress) {
        await _lastSave;
      }
    } catch (_) {}
  }

  // Attachments API
  Future<void> loadAttachments(String contractId) async {
    _attachments[contractId] = await _attachmentsRepo.list(contractId);
    notifyListeners();
  }

  Future<Attachment> addAttachmentFromPath(String contractId, String sourcePath, {String? name}) async {
    final a = await _attachmentsRepo.importFromPath(contractId, sourcePath, overrideName: name);
    final list = _attachments.putIfAbsent(contractId, () => []);
    list.add(a);
    notifyListeners();
    return a;
  }

  Future<Attachment> addAttachmentFromBytes(String contractId, List<int> bytes, {required String extension, String? name}) async {
    final a = await _attachmentsRepo.saveBytes(contractId, bytes, extension: extension, overrideName: name);
    final list = _attachments.putIfAbsent(contractId, () => []);
    list.add(a);
    notifyListeners();
    return a;
  }

  Future<void> deleteAttachment(String contractId, Attachment a) async {
    await _attachmentsRepo.delete(contractId, a);
    _attachments[contractId]?.removeWhere((x) => x.path == a.path);
    notifyListeners();
  }

  Future<Attachment> renameAttachment(String contractId, Attachment a, String newName) async {
    final r = await _attachmentsRepo.rename(contractId, a, newName);
    final list = _attachments[contractId];
    if (list != null) {
      final i = list.indexWhere((x) => x.id == a.id);
      if (i != -1) list[i] = r;
    }
    notifyListeners();
    return r;
  }
}

class WrongPassphraseError implements Exception {
  const WrongPassphraseError();
  @override
  String toString() => 'WrongPassphraseError';
}

String _hexFromBytes(List<int> bytes) {
  const hex = '0123456789abcdef';
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(hex[(b >> 4) & 0xF]);
    out.write(hex[b & 0xF]);
  }
  return out.toString();
}

