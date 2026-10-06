import 'dart:io';
import 'package:crypto/crypto.dart';

class SmartHasher {
  /// Computes a full byte-stream SHA-256 hash
  static Future<String> computeHash(File file, {bool isVideo = false}) async {
    return await _computeFullStreamHash(file);
  }

  /// Full file streaming SHA-256 calculation (memory efficient)
  static Future<String> _computeFullStreamHash(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
