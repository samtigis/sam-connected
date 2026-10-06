import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  static String? _cachedDeviceId;
  static String? _cachedDeviceLabel;

  /// Returns a clean, unique, and user-friendly ID for this device
  /// Examples: "iPhone_13_Pro_Max", "iPad_Air", "Android_Pixel_7"
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('persistent_client_device_id');
    if (stored != null && stored.isNotEmpty) {
      _cachedDeviceId = stored;
      return stored;
    }

    final deviceInfo = DeviceInfoPlugin();
    String detectedName = '';

    try {
      if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        final model = ios.model.trim().isNotEmpty ? ios.model.trim() : 'iOS';
        final name = ios.name.trim();
        final vendor = (ios.identifierForVendor ?? '').replaceAll('-', '');
        final shortVendor = vendor.length >= 4 ? vendor.substring(0, 4).toUpperCase() : '';

        if (name.isNotEmpty && !name.toLowerCase().contains('localhost')) {
          if ((name == 'iPhone' || name == 'iPad') && shortVendor.isNotEmpty) {
            detectedName = '${name}_$shortVendor';
          } else {
            detectedName = name;
          }
        } else {
          detectedName = shortVendor.isNotEmpty ? '${model}_$shortVendor' : model;
        }
      } else if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        final brand = android.brand.trim();
        final model = android.model.trim();
        detectedName = '$brand $model'.trim();
      } else if (Platform.isMacOS) {
        final mac = await deviceInfo.macOsInfo;
        detectedName = mac.computerName;
      } else if (Platform.isWindows) {
        final win = await deviceInfo.windowsInfo;
        detectedName = win.computerName;
      }
    } catch (_) {}

    if (detectedName.isEmpty) {
      detectedName = Platform.isIOS ? 'Apple_Device' : 'Client_Device';
    }

    // Format clean ID (alphanumeric, underscores and hyphens only)
    String cleanId = detectedName
        .replaceAll(RegExp(r"[^a-zA-Z0-9_\-\s]"), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');

    if (cleanId.isEmpty) {
      cleanId = 'Device_${DateTime.now().millisecondsSinceEpoch % 10000}';
    }

    await prefs.setString('persistent_client_device_id', cleanId);
    _cachedDeviceId = cleanId;
    return cleanId;
  }

  /// Returns a short display label for the UI (e.g. "iPhone", "iPad", "Android")
  static Future<String> getDeviceLabel() async {
    if (_cachedDeviceLabel != null) return _cachedDeviceLabel!;
    final id = await getDeviceId();
    final lower = id.toLowerCase();
    if (lower.contains('ipad')) {
      _cachedDeviceLabel = 'iPad';
    } else if (lower.contains('iphone')) {
      _cachedDeviceLabel = 'iPhone';
    } else if (lower.contains('android')) {
      _cachedDeviceLabel = 'Android';
    } else {
      _cachedDeviceLabel = id;
    }
    return _cachedDeviceLabel!;
  }
}
