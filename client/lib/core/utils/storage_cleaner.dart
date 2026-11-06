import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

class StorageCleaner {
  /// Clears PhotoManager cached files, temporary directory, and app cache directory
  static Future<int> clearAllCaches() async {
    int bytesFreed = 0;
    try {
      // 1. Clear PhotoManager file caches (where iOS PhotoKit exports photos/videos)
      await PhotoManager.clearFileCache();
    } catch (e) {
      debugPrint('[StorageCleaner] clearFileCache error: $e');
    }

    try {
      // 2. Clear Temporary Directory
      final tempDir = await getTemporaryDirectory();
      bytesFreed += await _deleteDirectoryContents(tempDir);
    } catch (e) {
      debugPrint('[StorageCleaner] clear tempDir error: $e');
    }

    try {
      // 3. Clear Application Cache Directory
      final cacheDir = await getApplicationCacheDirectory();
      bytesFreed += await _deleteDirectoryContents(cacheDir);
    } catch (e) {
      debugPrint('[StorageCleaner] clear cacheDir error: $e');
    }

    debugPrint('[StorageCleaner] Freed $bytesFreed bytes from cache/temp');
    return bytesFreed;
  }

  /// Calculates the total size of cached files
  static Future<int> getCacheSize() async {
    int total = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      total += await _getDirectorySize(tempDir);
    } catch (_) {}

    try {
      final cacheDir = await getApplicationCacheDirectory();
      total += await _getDirectorySize(cacheDir);
    } catch (_) {}

    return total;
  }

  static Future<int> _deleteDirectoryContents(Directory dir) async {
    int deletedBytes = 0;
    if (!await dir.exists()) return 0;
    try {
      final entries = dir.listSync(recursive: false);
      for (final entry in entries) {
        try {
          if (entry is File) {
            deletedBytes += await entry.length();
            await entry.delete();
          } else if (entry is Directory) {
            deletedBytes += await _getDirectorySize(entry);
            await entry.delete(recursive: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
    return deletedBytes;
  }

  static Future<int> _getDirectorySize(Directory dir) async {
    int total = 0;
    if (!await dir.exists()) return 0;
    try {
      final entries = dir.listSync(recursive: true);
      for (final entry in entries) {
        if (entry is File) {
          try {
            total += await entry.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }
}
