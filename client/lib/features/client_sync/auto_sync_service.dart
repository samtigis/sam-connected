import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_coordinator.dart';

class AutoSyncService extends ChangeNotifier {
  static const String _keyAutoSyncEnabled = 'auto_sync_enabled';
  static const String _keySyncOnAppOpen = 'sync_on_app_open';
  static const String _keySyncInterval = 'sync_interval_minutes';
  static const String _keyWifiOnly = 'sync_wifi_only';
  static const String _keyLastSyncTime = 'sync_last_time';
  static const String _keyLastSyncStatus = 'sync_last_status';

  final SyncCoordinator _syncCoordinator;
  Timer? _periodicTimer;
  Timer? _changeDebounceTimer;
  bool _isObservingPhotos = false;

  bool _autoSyncEnabled = true;
  bool _syncOnAppOpen = true;
  int _syncIntervalMinutes = 15; // 0 = manual/on app open, 15, 30, 60, 360, 1440
  bool _wifiOnly = true;
  DateTime? _lastSyncTime;
  String _lastSyncStatus = 'Belum pernah sinkronisasi';
  bool _isAutoSyncRunning = false;

  bool get autoSyncEnabled => _autoSyncEnabled;
  bool get syncOnAppOpen => _syncOnAppOpen;
  int get syncIntervalMinutes => _syncIntervalMinutes;
  bool get wifiOnly => _wifiOnly;
  DateTime? get lastSyncTime => _lastSyncTime;
  String get lastSyncStatus => _lastSyncStatus;
  bool get isAutoSyncRunning => _isAutoSyncRunning;

  AutoSyncService(this._syncCoordinator) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _autoSyncEnabled = prefs.getBool(_keyAutoSyncEnabled) ?? true;
    _syncOnAppOpen = prefs.getBool(_keySyncOnAppOpen) ?? true;
    _syncIntervalMinutes = prefs.getInt(_keySyncInterval) ?? 15;
    _wifiOnly = prefs.getBool(_keyWifiOnly) ?? true;

    final lastTimeStr = prefs.getString(_keyLastSyncTime);
    if (lastTimeStr != null) {
      _lastSyncTime = DateTime.tryParse(lastTimeStr);
    }
    _lastSyncStatus = prefs.getString(_keyLastSyncStatus) ?? 'Belum pernah sinkronisasi';

    _setupTimer();
    notifyListeners();
  }

  void _setupTimer() {
    _periodicTimer?.cancel();
    if (!_autoSyncEnabled || _syncIntervalMinutes <= 0) return;

    _periodicTimer = Timer.periodic(
      Duration(minutes: _syncIntervalMinutes),
      (_) => triggerAutoSync(reason: 'Jadwal Berkala (${_syncIntervalMinutes}m)'),
    );
  }

  Future<void> setAutoSyncEnabled(bool enabled) async {
    _autoSyncEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSyncEnabled, enabled);
    _setupTimer();
    notifyListeners();
  }

  Future<void> setSyncOnAppOpen(bool enabled) async {
    _syncOnAppOpen = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySyncOnAppOpen, enabled);
    notifyListeners();
  }

  Future<void> setSyncInterval(int minutes) async {
    _syncIntervalMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySyncInterval, minutes);
    _setupTimer();
    notifyListeners();
  }

  Future<void> setWifiOnly(bool enabled) async {
    _wifiOnly = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWifiOnly, enabled);
    notifyListeners();
  }

  /// Triggers auto-sync if conditions are met
  Future<void> triggerAutoSync({String reason = 'Otomatis'}) async {
    if (!_autoSyncEnabled && reason != 'Manual') return;
    if (_isAutoSyncRunning || _syncCoordinator.state.isSyncing) return;

    _isAutoSyncRunning = true;
    notifyListeners();

    try {
      await _syncCoordinator.startSync();
      _lastSyncTime = DateTime.now();
      final uploaded = _syncCoordinator.state.uploadedCount;
      if (_syncCoordinator.state.errorCount > 0) {
        _lastSyncStatus = 'Sinkronisasi selesai dengan ${_syncCoordinator.state.errorCount} kesalahan';
      } else if (uploaded > 0) {
        _lastSyncStatus = 'Berhasil mencadangkan $uploaded foto baru';
      } else {
        _lastSyncStatus = 'Semua foto galeri aman tercadangkan';
      }
    } catch (e) {
      _lastSyncStatus = 'Error: $e';
    } finally {
      _isAutoSyncRunning = false;
      final prefs = await SharedPreferences.getInstance();
      if (_lastSyncTime != null) {
        await prefs.setString(_keyLastSyncTime, _lastSyncTime!.toIso8601String());
      }
      await prefs.setString(_keyLastSyncStatus, _lastSyncStatus);
      notifyListeners();
    }
  }

  /// Invoked when app resumes from background to foreground
  void onAppResume() {
    if (_autoSyncEnabled && _syncOnAppOpen) {
      triggerAutoSync(reason: 'Aplikasi Dibuka');
    }
  }

  /// Listens to iOS & Android native photo library changes in real-time (PhotoKit)
  void startPhotoChangeObserver() {
    if (_isObservingPhotos) return;
    try {
      PhotoManager.addChangeCallback(_onPhotoLibraryChange);
      PhotoManager.startChangeNotify();
      _isObservingPhotos = true;
    } catch (e) {
      if (kDebugMode) print('Failed to start PhotoManager change notify: $e');
    }
  }

  void stopPhotoChangeObserver() {
    if (!_isObservingPhotos) return;
    try {
      PhotoManager.removeChangeCallback(_onPhotoLibraryChange);
      PhotoManager.stopChangeNotify();
    } catch (_) {}
    _changeDebounceTimer?.cancel();
    _isObservingPhotos = false;
  }

  void _onPhotoLibraryChange(MethodCall call) {
    if (!_autoSyncEnabled) return;
    // Debounce 4 seconds so camera app finishes saving the photo/video file
    _changeDebounceTimer?.cancel();
    _changeDebounceTimer = Timer(const Duration(seconds: 4), () {
      triggerAutoSync(reason: 'Deteksi Media Baru di Galeri (PhotoKit Live)');
    });
  }

  /// Invoked when server is discovered on local Wi-Fi network
  void onServerDiscovered() {
    if (_autoSyncEnabled && !_isAutoSyncRunning && !_syncCoordinator.state.isSyncing) {
      triggerAutoSync(reason: 'Server Terdeteksi di Jaringan Wi-Fi');
    }
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _changeDebounceTimer?.cancel();
    stopPhotoChangeObserver();
    super.dispose();
  }
}
