import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../domain/models.dart';
import '../domain/attachments.dart';
import 'attachment_repository.dart';
import 'notes_store.dart';
import '../../profile/data/user_profile.dart';
import '../../profile/data/profile_store.dart';
import '../../profile/data/settings_store.dart';
import '../../../core/notifications/notification_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'dart:io';
import 'package:timezone/timezone.dart' as tz;

class AppState extends ChangeNotifier {
  final AttachmentRepository _attachmentsRepo = AttachmentRepository();
  final NotesStore _notesStore = NotesStore();
  final ProfileStore _profileStore = ProfileStore();
  final SettingsStore _settingsStore = SettingsStore();
  bool _attachmentsGridPreferred = false;
  ThemeMode _themeMode = ThemeMode.system;
  // Reminders & notifications
  bool _remindersEnabled = true;
  bool _pushEnabled = true;
  bool _inAppBannerEnabled = true;
  Set<int> _reminderDays = {7, 14, 30};
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);
  // Privacy controls (defaults)
  bool _blockScreenshots = true;
  bool _allowShare = true;
  bool _allowDownload = true;
  bool _requireBiometricExport = false;
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
      categoryId: 'cat_subs',
      costAmount: 12.99,
      costCurrency: '€',
      billingCycle: BillingCycle.monthly,
      paymentMethod: PaymentMethod.creditCard,
      isOpenEnded: true,
      startDate: DateTime.now().subtract(const Duration(days: 400)),
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
    _hydrateNotes();
    _hydrateProfile();
    _hydrateSettings();
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
    final bio = s['requireBiometricExport'] as bool?;
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
    if (bio != null) _requireBiometricExport = bio;
    // One-time in-session migration: stamp missing deletedAt so retention can apply
    _stampDeletedAtIfMissing();
    notifyListeners();
    // Run an initial sweep after hydration
    _autoEmptyTrashSweep();
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
      'requireBiometricExport': _requireBiometricExport,
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
  bool get requireBiometricExport => _requireBiometricExport;

  void setBlockScreenshots(bool v) { _blockScreenshots = v; notifyListeners(); _persistSettings(); }
  void setAllowShare(bool v) { _allowShare = v; notifyListeners(); _persistSettings(); }
  void setAllowDownload(bool v) { _allowDownload = v; notifyListeners(); _persistSettings(); }
  void setRequireBiometricExport(bool v) { _requireBiometricExport = v; notifyListeners(); _persistSettings(); }

  // Export all data into a zip inside app documents
  Future<String> exportAll() async {
    final dir = await getApplicationDocumentsDirectory();
    final exportPath = '${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.zip';
    final encoder = ZipFileEncoder();
    encoder.create(exportPath);
    try {
      for (final name in ['settings.json', 'notes.json', 'profile.json']) {
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
    for (final name in ['settings.json', 'notes.json', 'profile.json']) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) { try { await f.delete(); } catch (_) {} }
    }
    final attachmentsDir = Directory('${dir.path}/attachments');
    if (await attachmentsDir.exists()) { try { await attachmentsDir.delete(recursive: true); } catch (_) {} }
    _attachments.clear();
    _notesEditedAt.clear();
    _attachmentsGridPreferred = false;
    _themeMode = ThemeMode.system;
    _remindersEnabled = true;
    _pushEnabled = true;
    _inAppBannerEnabled = true;
    _reminderDays = {7,14,30};
    _reminderTime = const TimeOfDay(hour: 9, minute: 0);
    _blockScreenshots = true;
    _allowShare = true;
    _allowDownload = true;
    _requireBiometricExport = false;
    notifyListeners();
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
    }
  }

  void purgeContract(String id) {
    _contracts.removeWhere((e) => e.id == id);
    _attachments.remove(id);
    _notesEditedAt.remove(id);
    Future.microtask(() => _notesStore.deleteNote(id));
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

  void _stampDeletedAtIfMissing() {
    for (var i = 0; i < _contracts.length; i++) {
      final c = _contracts[i];
      if (c.isDeleted && c.deletedAt == null) {
        _contracts[i] = c.copyWith(deletedAt: DateTime.now());
      }
    }
  }

  void purgeAll() {
    _contracts.removeWhere((e) => e.isDeleted);
    notifyListeners();
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
    return id;
  }

  void renameCategory(String id, String newName) {
    final i = _categories.indexWhere((c) => c.id == id);
    if (i != -1) {
      final old = _categories[i];
      _categories[i] = ContractGroup(id: old.id, name: newName, builtIn: old.builtIn);
      notifyListeners();
    }
  }

  int deleteCategory(String id) {
    if (_categories.any((c) => c.id == id && c.builtIn)) return 0; // keep defaults
    final moved = _contracts.where((c) => c.categoryId == id).toList();
    for (final c in moved) {
      updateContract(c.copyWith(categoryId: 'cat_other'));
    }
    _categories.removeWhere((c) => c.id == id);
    notifyListeners();
    return moved.length;
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
