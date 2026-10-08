import 'dart:io';
import 'package:flutter/services.dart';

class BackgroundTaskManager {
  static const MethodChannel _channel = MethodChannel('com.samtigis.client/background_task');
  static Future<void> Function()? onBackgroundRefreshRequested;
  static bool _initialized = false;

  /// Registers native background listener for BGAppRefreshTask & BGProcessingTask
  static void initialize({Future<void> Function()? onRefresh}) {
    if (!Platform.isIOS) return;
    onBackgroundRefreshRequested = onRefresh;

    if (!_initialized) {
      _initialized = true;
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
  }

  /// Keep screen on during active foreground syncing to prevent sleep
  static Future<void> setKeepScreenOn(bool keepOn) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('setIdleTimerDisabled', keepOn);
    } catch (_) {}
  }

  /// Request iOS to allow execution in background while syncing (gives ~30s extension)
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
