import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppRole {
  unselected,
  serverHost,
  clientUploader,
}

class RoleController extends ChangeNotifier {
  static const String _roleKey = 'app_role';
  static const String _storagePathKey = 'server_storage_path';
  static const String _serverPortKey = 'server_port';

  AppRole _currentRole = AppRole.unselected;
  bool _isLoading = true;
  String _storagePath = '';
  int _serverPort = 8080;

  AppRole get currentRole => _currentRole;
  bool get isLoading => _isLoading;
  bool get isConfigured => _currentRole != AppRole.unselected;
  bool get isServer => _currentRole == AppRole.serverHost;
  bool get isClient => _currentRole == AppRole.clientUploader;
  String get storagePath => _storagePath;
  int get serverPort => _serverPort;

  static bool get isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  RoleController() {
    loadRole();
  }

  Future<void> loadRole() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final roleString = prefs.getString(_roleKey);

    if (roleString == 'serverHost') {
      _currentRole = AppRole.serverHost;
    } else if (roleString == 'clientUploader') {
      _currentRole = AppRole.clientUploader;
    } else {
      _currentRole = AppRole.unselected;
    }

    _storagePath = prefs.getString(_storagePathKey) ?? '';
    _serverPort = prefs.getInt(_serverPortKey) ?? 8080;

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setRole(AppRole role, {String? customStoragePath, int? port}) async {
    final prefs = await SharedPreferences.getInstance();

    if (role == AppRole.serverHost && !isDesktopPlatform) {
      throw UnsupportedError('Server/Host mode is only supported on Desktop (Windows/macOS/Linux).');
    }

    _currentRole = role;
    if (role == AppRole.serverHost) {
      await prefs.setString(_roleKey, 'serverHost');
      if (customStoragePath != null && customStoragePath.isNotEmpty) {
        _storagePath = customStoragePath;
        await prefs.setString(_storagePathKey, customStoragePath);
      }
      if (port != null) {
        _serverPort = port;
        await prefs.setInt(_serverPortKey, port);
      }
    } else if (role == AppRole.clientUploader) {
      await prefs.setString(_roleKey, 'clientUploader');
    } else {
      await prefs.remove(_roleKey);
    }

    notifyListeners();
  }

  Future<void> updateStoragePath(String path) async {
    _storagePath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storagePathKey, path);
    notifyListeners();
  }

  Future<void> resetRole() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    _currentRole = AppRole.unselected;
    notifyListeners();
  }
}
