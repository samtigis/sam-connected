import 'dart:io';
import 'package:flutter/services.dart';

class BackgroundTaskManager {
  static const MethodChannel _channel = MethodChannel('com.samtigis.client/background_task');
  static Future<void> Function()? onBackgroundRefreshRequested;
  static bool _initialized = false;

  /// Initializes native background listener for BGAppRefreshTask
  static void initialize({Future<void> Function()? onRefresh}) {
    if (!Platform.isIOS || _initialized) return;
    _initialized = true;
    onBackgroundRefreshRequested = onRefresh;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onBackgroundRefresh') {
        if (onBackgroundRefreshRequested != null) {
          await onBackgroundRefreshRequested!();
        }
        return true;
      }
      return null;
    });
  }

  /// Request iOS to allow execution in background while syncing
  static Future<void> beginBackgroundTask() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('beginBackgroundTask');
    } catch (_) {}
  }

  /// Inform iOS that background work has completed
  static Future<void> endBackgroundTask() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('endBackgroundTask');
    } catch (_) {}
  }
}
