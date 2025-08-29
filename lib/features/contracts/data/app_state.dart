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
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'dart:io';
import 'package:timezone/timezone.dart' as tz;
import 'attachment_crypto.dart';
import '../../../core/crypto/key_service.dart';
import '../../../core/crypto/passphrase_service.dart';
import '../../../core/crypto/provisioning_service.dart';

class AppState extends ChangeNotifier {
  final AttachmentRepository _attachmentsRepo = AttachmentRepository();
  final ContractsStore _contractsStore = ContractsStore();
  final NotesStore _notesStore = NotesStore();
  final ProfileStore _profileStore = ProfileStore();
  final SettingsStore _settingsStore = SettingsStore();
  bool _attachmentsGridPreferred = false;
  ThemeMode _themeMode = ThemeMode.system;
  // Initial hydration gate
  bool _isLoading = true;
  bool get isLoading => _isLoading;
  // Locked state: encrypted data present but no master key installed
  bool _isLocked = false;
  bool get isLocked => _isLocked;
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
    const ContractGroup(id: 'cat_other', name: 'Other', builtIn: true),
  ];

  final List<Contract> _contracts = [
    Contract(
      id: 'c1',
      title: 'Electricity',
      provider: 'GreenPower GmbH',
      customerNumber: 'EL-492031',
      categoryId: 'cat_home',
      costAmount: 62.90,
      costCurrency: '€',
      billingCycle: BillingCycle.monthly,
      paymentMethod: PaymentMethod.sepa,
      startDate: DateTime.now().subtract(const Duration(days: 120)),
      endDate: DateTime.now().add(const Duration(days: 240)),
    ),
    Contract(
      id: 'c2',
      title: 'Netflix',
      provider: 'Netflix',
      customerNumber: 'NF-882110',
      categoryId: 'cat_subs',
      costAmount: 12.99,
      costCurrency: '€',
      billingCycle: BillingCycle.monthly,
      paymentMethod: PaymentMethod.creditCard,
      isOpenEnded: true,
      startDate: DateTime.now().subtract(const Duration(days: 400)),
    ),
    Contract(
      id: 'c3',
      title: 'Gas',
      provider: 'CityGas AG',
      customerNumber: 'GA-771204',
      categoryId: 'cat_home',
      costAmount: 48.50,
      costCurrency: '€',
      billingCycle: BillingCycle.monthly,
      paymentMethod: PaymentMethod.sepa,
      startDate: DateTime.now().subtract(const Duration(days: 200)),
      endDate: DateTime.now().add(const Duration(days: 165)),
    ),
    Contract(
      id: 'c4',
      title: 'Rent',
      provider: 'Muster Immobilien GmbH',
      customerNumber: 'RE-2023-015',
      categoryId: 'cat_home',
      costAmount: 980.00,
      costCurrency: '€',
      billingCycle: BillingCycle.monthly,
      paymentMethod: PaymentMethod.sepa,
      isOpenEnded: true,
      startDate: DateTime.now().subtract(const Duration(days: 800)),
    ),
    Contract(
      id: 'c5',
      title: 'Gym Membership',
      provider: 'FitClub',
      customerNumber: 'GYM-55421',
      categoryId: 'cat_subs',
      costAmount: 34.90,
      costCurrency: '€',
      billingCycle: BillingCycle.monthly,
      paymentMethod: PaymentMethod.creditCard,
      isOpenEnded: true,
      startDate: DateTime.now().subtract(const Duration(days: 250)),
    ),
    Contract(
      id: 'c6',
      title: 'Car Insurance',
      provider: 'AutoProtect',
      customerNumber: 'CAR-INS-90021',
      categoryId: 'cat_other',
      costAmount: 520.00,
      costCurrency: '€',
      billingCycle: BillingCycle.yearly,
      paymentMethod: PaymentMethod.bankTransfer,
      startDate: DateTime.now().subtract(const Duration(days: 500)),
      endDate: DateTime.now().add(const Duration(days: 200)),
    ),
    Contract(
      id: 'c7',
      title: 'Internet',
      provider: 'TeleNet GmbH',
      customerNumber: 'NET-003942',
      categoryId: 'cat_home',
      costAmount: 39.99,
      costCurrency: '€',
      billingCycle: BillingCycle.monthly,
      paymentMethod: PaymentMethod.sepa,
      isOpenEnded: true,
      startDate: DateTime.now().subtract(const Duration(days: 600)),
    ),
    Contract(
      id: 'c8',
      title: 'Mobile Plan',
      provider: 'MobiCom',
      customerNumber: 'MB-221177',
      categoryId: 'cat_subs',
      costAmount: 24.99,
      costCurrency: '€',
      billingCycle: BillingCycle.monthly,
      paymentMethod: PaymentMethod.creditCard,
      isOpenEnded: true,
      startDate: DateTime.now().subtract(const Duration(days: 300)),
    ),
  ];

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

  void _init() {
    _startupUnlockCheck().then((unlocked) {
      if (!unlocked) {
        _isLocked = true;
        _isLoading = false;
        notifyListeners();
        return;
      }
      Future.wait([
        _hydrateContracts(),
        _hydrateNotes(),
        _hydrateProfile(),
        _hydrateSettings(),
      ]).whenComplete(() {
        _isLoading = false;
        notifyListeners();
      });
    });
  }

  Future<bool> _startupUnlockCheck() async {
    // If MK present, we are unlocked
    if (await KeyService.instance.hasMasterKey()) return true;
    // Try auto-unlock using locally provisioned wrapped MK
    final auto = await ProvisioningService.instance.tryAutoUnlock();
    if (auto) return true;
    // If an EMK or encrypted stores are present, we need a passphrase before hydration
    final dir = await getApplicationDocumentsDirectory();
    final emk = File('${dir.path}/emk.json');
    if (await emk.exists()) return false;
    // Also check for existence of encrypted stores
    for (final n in ['contracts.enc','notes.enc','settings.enc','profile.enc']) {
      if (await File('${dir.path}/$n').exists()) return false;
    }
    // No encrypted data found; create MK on first use and proceed
    return true;
  }

  Future<bool> unlockWithPassphrase(String passphrase) async {
    final ok = await PassphraseService.unlockAndStore(passphrase);
    if (!ok) return false;
    _isLocked = false;
    _isLoading = true;
    notifyListeners();
    await _hydrateContracts();
    await _hydrateNotes();
    await _hydrateProfile();
    await _hydrateSettings();
    await _rescheduleReminders();
    _isLoading = false;
    notifyListeners();
    return true;
  }

  Future<void> _hydrateContracts() async {
    final snap = await _contractsStore.load();
    if (snap != null) {
      _categories
        ..clear()
        ..addAll(snap.categories);
      _ensureBuiltinCategories();
      // Load persisted data; if empty, seed demo for a realistic UI
      final loaded = List<Contract>.from(snap.contracts);
      if (loaded.isEmpty) {
        _contracts
          ..clear()
          ..addAll(_demoContracts());
        await _persistContracts();
      } else {
        _contracts
          ..clear()
          ..addAll(loaded);
      }
      notifyListeners();
    } else {
      // First run: seed demo data to make the app feel populated
      _contracts
        ..clear()
        ..addAll(_demoContracts());
      await _persistContracts();
      notifyListeners();
    }
  }

  // Removed unused _looksLikeDemoSeed helper

  List<Contract> _demoContracts() {
    final now = DateTime.now();
    return [
      Contract(
        id: 'c1',
        title: 'Electricity',
        provider: 'GreenPower GmbH',
        customerNumber: 'EL-492031',
        categoryId: 'cat_home',
        costAmount: 62.90,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.sepa,
        startDate: now.subtract(const Duration(days: 120)),
        endDate: now.add(const Duration(days: 240)),
      ),
      Contract(
        id: 'c2',
        title: 'Netflix',
        provider: 'Netflix',
        customerNumber: 'NF-882110',
        categoryId: 'cat_subs',
        costAmount: 12.99,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.creditCard,
        isOpenEnded: true,
        startDate: now.subtract(const Duration(days: 400)),
      ),
      Contract(
        id: 'c3',
        title: 'Gas',
        provider: 'CityGas AG',
        customerNumber: 'GA-771204',
        categoryId: 'cat_home',
        costAmount: 48.50,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.sepa,
        startDate: now.subtract(const Duration(days: 200)),
        endDate: now.add(const Duration(days: 165)),
      ),
      Contract(
        id: 'c4',
        title: 'Rent',
        provider: 'Muster Immobilien GmbH',
        customerNumber: 'RE-2023-015',
        categoryId: 'cat_home',
        costAmount: 980.00,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.sepa,
        isOpenEnded: true,
        startDate: now.subtract(const Duration(days: 800)),
      ),
      Contract(
        id: 'c5',
        title: 'Gym Membership',
        provider: 'FitClub',
        customerNumber: 'GYM-55421',
        categoryId: 'cat_subs',
        costAmount: 34.90,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.creditCard,
        isOpenEnded: true,
        startDate: now.subtract(const Duration(days: 250)),
      ),
      Contract(
        id: 'c6',
        title: 'Car Insurance',
        provider: 'AutoProtect',
        customerNumber: 'CAR-INS-90021',
        categoryId: 'cat_other',
        costAmount: 520.00,
        billingCycle: BillingCycle.yearly,
        paymentMethod: PaymentMethod.bankTransfer,
        startDate: now.subtract(const Duration(days: 500)),
        endDate: now.add(const Duration(days: 200)),
      ),
      Contract(
        id: 'c7',
        title: 'Internet',
        provider: 'TeleNet GmbH',
        customerNumber: 'NET-003942',
        categoryId: 'cat_home',
        costAmount: 39.99,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.sepa,
        isOpenEnded: true,
        startDate: now.subtract(const Duration(days: 600)),
      ),
      Contract(
        id: 'c8',
        title: 'Mobile Plan',
        provider: 'MobiCom',
        customerNumber: 'MB-221177',
        categoryId: 'cat_subs',
        costAmount: 24.99,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.creditCard,
        isOpenEnded: true,
        startDate: now.subtract(const Duration(days: 300)),
      ),
      Contract(
        id: 'c9',
        title: 'Water',
        provider: 'CityWater',
        customerNumber: 'WT-448210',
        categoryId: 'cat_home',
        costAmount: 28.40,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.sepa,
        isOpenEnded: true,
        startDate: now.subtract(const Duration(days: 500)),
      ),
      Contract(
        id: 'c10',
        title: 'Spotify',
        provider: 'Spotify',
        customerNumber: 'SP-339201',
        categoryId: 'cat_subs',
        costAmount: 9.99,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.creditCard,
        isOpenEnded: true,
        startDate: now.subtract(const Duration(days: 420)),
      ),
      Contract(
        id: 'c11',
        title: 'Amazon Prime',
        provider: 'Amazon',
        customerNumber: 'AM-778210',
        categoryId: 'cat_subs',
        costAmount: 89.00,
        billingCycle: BillingCycle.yearly,
        paymentMethod: PaymentMethod.creditCard,
        startDate: now.subtract(const Duration(days: 700)),
        endDate: now.add(const Duration(days: 60)),
      ),
      Contract(
        id: 'c12',
        title: 'Home Insurance',
        provider: 'SafeHome AG',
        customerNumber: 'HI-239910',
        categoryId: 'cat_other',
        costAmount: 210.00,
        billingCycle: BillingCycle.yearly,
        paymentMethod: PaymentMethod.bankTransfer,
        startDate: now.subtract(const Duration(days: 900)),
        endDate: now.add(const Duration(days: 330)),
      ),
      Contract(
        id: 'c13',
        title: 'Health Insurance',
        provider: 'HealthPlus',
        customerNumber: 'HL-550033',
        categoryId: 'cat_other',
        costAmount: 320.00,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.sepa,
        isOpenEnded: true,
        startDate: now.subtract(const Duration(days: 1000)),
      ),
      Contract(
        id: 'c14',
        title: 'iCloud Storage',
        provider: 'Apple',
        customerNumber: 'IC-002211',
        categoryId: 'cat_subs',
        costAmount: 2.99,
        billingCycle: BillingCycle.monthly,
        paymentMethod: PaymentMethod.creditCard,
        isOpenEnded: true,
        startDate: now.subtract(const Duration(days: 365)),
      ),
    ];
  }

  void _ensureBuiltinCategories() {
    // Make sure built-in categories exist at least once
    bool has(String id) => _categories.any((c) => c.id == id);
    if (!has('cat_home')) _categories.insert(0, const ContractGroup(id: 'cat_home', name: 'Home', builtIn: true));
    if (!has('cat_subs')) _categories.insert(1, const ContractGroup(id: 'cat_subs', name: 'Subscriptions', builtIn: true));
    if (!has('cat_other')) _categories.add(const ContractGroup(id: 'cat_other', name: 'Other', builtIn: true));
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
        orElse: () => const ContractGroup(id: 'cat_other', name: 'Other', builtIn: true),
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
    // Schedule reminders with stable IDs after hydration
    await _rescheduleReminders();
  }

  Future<void> _persistSettings() async {
    await _settingsStore.save({
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
    });
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
    final dir = await getApplicationDocumentsDirectory();
    final exportPath = '${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.zip';
    final encoder = ZipFileEncoder();
    encoder.create(exportPath);
    try {
      // Prefer encrypted stores; fall back to legacy plaintext if present
      final names = [
        'contracts.enc', 'contracts.json',
        'notes.enc', 'notes.json',
        'settings.enc', 'settings.json',
        'profile.enc', 'profile.json',
        'emk.json',
      ];
      for (final name in names) {
        final f = File('${dir.path}/$name');
        if (await f.exists()) encoder.addFile(f);
      }
      final attachmentsDir = Directory('${dir.path}/attachments');
      if (await attachmentsDir.exists()) {
        encoder.addDirectory(attachmentsDir);
      }
    } finally {
      encoder.close();
    }
    return exportPath;
  }

  // Wipe local data
  Future<void> wipeLocalData() async {
    final dir = await getApplicationDocumentsDirectory();
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
    // Also wipe crypto keys to render any leftover encrypted blobs unrecoverable
    try { await AttachmentCryptoService().wipeKey(); } catch (_) {}
    try { await KeyService.instance.wipeMasterKey(); } catch (_) {}
  }

  // Reset local contracts to the built-in demo dataset (for development/testing)
  Future<void> resetToDemoData() async {
    _attachments.clear();
    _notesEditedAt.clear();
    _contracts
      ..clear()
      ..addAll(_demoContracts());
    notifyListeners();
    await _persistContracts();
    await _rescheduleReminders();
  }

  // Import a previously exported zip and replace local data
  Future<bool> importFromZip(String zipPath, {required String passphrase}) async {
    final dir = await getApplicationDocumentsDirectory();
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      // Validate expected contents before destructive actions
      final names = archive.files.map((f) => f.name).toSet();
      final hasContracts = names.contains('contracts.enc') || names.contains('contracts.json');
      final hasEmk = names.contains('emk.json');
      // Enforce passphrase-protected imports only
      if (!hasContracts || !hasEmk) {
        return false; // essential files missing
      }
      // Wipe existing data first to avoid stale files
      await wipeLocalData();
      extractArchiveToDisk(archive, dir.path);
      // Require passphrase to unlock before hydration
      if (passphrase.isEmpty) return false;
      final ok = await PassphraseService.unlockAndStore(passphrase);
      if (!ok) return false; // wrong passphrase
    } catch (e) {
      return false;
    }
    // Rehydrate state from disk
    await _hydrateContracts();
    await _hydrateNotes();
    await _hydrateProfile();
    await _hydrateSettings();
    await _rescheduleReminders();
    notifyListeners();
    return true;
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
    final path = await _profileStore.saveAvatarFromPath(sourcePath);
    await updateProfile(_profile.copyWith(photoPath: path));
  }

  DateTime? lastNoteEditedAt(String contractId) => _notesEditedAt[contractId];

  Future<Uint8List> readAttachmentBytes(String contractId, Attachment a) async {
    return _attachmentsRepo.readDecrypted(contractId, a);
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
    _contracts.removeWhere((e) => e.id == id);
    _attachments.remove(id);
    _notesEditedAt.remove(id);
    Future.microtask(() => _notesStore.deleteNote(id));
    notifyListeners();
    NotificationService.instance.cancelForContract(id);
    _persistContracts();
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
    _contracts.removeWhere((e) => e.isDeleted);
    notifyListeners();
    _persistContracts();
  }

  String addCategory(String name) {
    final id = 'cat_${DateTime.now().microsecondsSinceEpoch}';
    final otherIndex = _categories.indexWhere((c) => c.id == 'cat_other');
    final insertAt = otherIndex == -1 ? _categories.length : otherIndex;
    _categories.insert(
      insertAt,
      ContractGroup(id: id, name: name, builtIn: false),
    );
    notifyListeners();
    _persistContracts();
    return id;
  }

  void renameCategory(String id, String newName) {
    final i = _categories.indexWhere((c) => c.id == id);
    if (i != -1) {
      final old = _categories[i];
      _categories[i] = ContractGroup(id: old.id, name: newName, builtIn: old.builtIn);
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
    notifyListeners();
    _persistContracts();
    return moved.length;
  }

  Future<void> _persistContracts() async {
    await _contractsStore.save(_categories, _contracts);
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
