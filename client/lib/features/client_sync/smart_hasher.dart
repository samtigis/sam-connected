import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class SmartHasher {
  static const int largeFileThreshold = 50 * 1024 * 1024; // 50 Megabytes
  static const int sampleBlockSize = 64 * 1024; // 64 Kilobytes

  /// Computes a smart SHA-256 hash according to asset type and size:
  /// - Photos (< 50MB): Full byte-stream SHA-256
  /// - Videos (>= 50MB): High-efficiency hash (FileSize + First 64KB + Last 64KB)
  static Future<String> computeHash(File file, {bool isVideo = false}) async {
    final int fileSize = await file.length();

    if (isVideo && fileSize >= largeFileThreshold) {
      return await _computePowerSavingHash(file, fileSize);
    } else {
      return await _computeFullStreamHash(file);
    }
  }

  /// Full file streaming SHA-256 calculation (memory efficient)
  static Future<String> _computeFullStreamHash(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Battery-efficient hash for heavy videos:
  /// Hash = SHA256( ASCII(file_size) + first_64KB + last_64KB )
  static Future<String> _computePowerSavingHash(File file, int fileSize) async {
    final RandomAccessFile raf = await file.open(mode: FileMode.read);
    try {
      final List<int> bytesToHash = [];

      // 1. Add file size prefix
      bytesToHash.addAll(utf8.encode('fastvideo:$fileSize:'));

      // 2. Read first 64KB
      final int firstReadSize = fileSize < sampleBlockSize ? fileSize : sampleBlockSize;
      final Uint8List firstBlock = await raf.read(firstReadSize);
      bytesToHash.addAll(firstBlock);

      // 3. Read last 64KB
      if (fileSize > sampleBlockSize) {
        final int seekPos = fileSize - sampleBlockSize;
        await raf.setPosition(seekPos);
        final Uint8List lastBlock = await raf.read(sampleBlockSize);
        bytesToHash.addAll(lastBlock);
      }

      final digest = sha256.convert(bytesToHash);
      return digest.toString();
    } finally {
      await raf.close();
    }
  }
}
