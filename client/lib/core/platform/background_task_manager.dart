import 'dart:io';
import 'package:flutter/services.dart';

class BackgroundTaskManager {
  static const MethodChannel _channel = MethodChannel('com.samtigis.client/background_task');

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
