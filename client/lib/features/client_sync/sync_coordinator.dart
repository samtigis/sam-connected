import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/database/local_database.dart';
import '../../core/network/api_client.dart';
import '../../core/platform/background_task_manager.dart';
import '../../core/utils/device_identity.dart';
import 'gallery_scanner_service.dart';

class SyncProgressState {
  final bool isSyncing;
  final String statusMessage;
  final String currentFileName;
  final double currentProgress; // 0.0 - 1.0
  final int totalToUpload;
  final int uploadedCount;
  final int skippedCount;
  final int errorCount;
  final List<String> logs;

  SyncProgressState({
    this.isSyncing = false,
    this.statusMessage = 'Idle',
    this.currentFileName = '',
    this.currentProgress = 0.0,
    this.totalToUpload = 0,
    this.uploadedCount = 0,
    this.skippedCount = 0,
    this.errorCount = 0,
    this.logs = const [],
  });

  SyncProgressState copyWith({
    bool? isSyncing,
    String? statusMessage,
    String? currentFileName,
    double? currentProgress,
    int? totalToUpload,
    int? uploadedCount,
    int? skippedCount,
    int? errorCount,
    List<String>? logs,
  }) {
    return SyncProgressState(
      isSyncing: isSyncing ?? this.isSyncing,
      statusMessage: statusMessage ?? this.statusMessage,
      currentFileName: currentFileName ?? this.currentFileName,
      currentProgress: currentProgress ?? this.currentProgress,
      totalToUpload: totalToUpload ?? this.totalToUpload,
      uploadedCount: uploadedCount ?? this.uploadedCount,
      skippedCount: skippedCount ?? this.skippedCount,
      errorCount: errorCount ?? this.errorCount,
      logs: logs ?? this.logs,
    );
  }
}

class SyncCoordinator extends ChangeNotifier {
  final ApiClient apiClient;
  final GalleryScannerService scannerService;
  final LocalDatabase localDb = LocalDatabase.instance;

  SyncProgressState _state = SyncProgressState();
  bool _cancelRequested = false;

  SyncProgressState get state => _state;

  SyncCoordinator({
    required this.apiClient,
    required this.scannerService,
  });

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final logLine = '[$timestamp] $message';
    final updatedLogs = List<String>.from(_state.logs)..insert(0, logLine);
    if (updatedLogs.length > 50) {
      updatedLogs.removeLast();
    }
    _state = _state.copyWith(logs: updatedLogs);
    notifyListeners();
  }

  Future<String> _getDeviceId() async {
    return await DeviceIdentity.getDeviceId();
  }

  void cancelSync() {
    _cancelRequested = true;
    _state = _state.copyWith(
      isSyncing: false,
      statusMessage: 'Sync cancellation requested...',
    );
    notifyListeners();
  }

  /// Executes full end-to-end sync cycle:
  /// 1. Gallery Scan
  /// 2. Batch Pre-flight Check (50 hashes/batch)
  /// 3. Upload only missing assets
  Future<void> startSync() async {
    if (_state.isSyncing) return;

    _cancelRequested = false;
    _state = SyncProgressState(
      isSyncing: true,
      statusMessage: 'Memverifikasi izin galeri...',
      logs: _state.logs,
    );
    notifyListeners();

    await BackgroundTaskManager.setKeepScreenOn(true);
    await BackgroundTaskManager.beginBackgroundTask();

    try {
      final hasPermission = await scannerService.requestPermission();
      if (!hasPermission) {
        _log('Izin akses galeri ditolak oleh pengguna.');
        _state = _state.copyWith(
          isSyncing: false,
          statusMessage: 'Izin galeri ditolak',
        );
        notifyListeners();
        return;
      }

      // Check server connectivity
      _state = _state.copyWith(statusMessage: 'Menghubungkan ke server...');
      notifyListeners();
      try {
        final pingRes = await apiClient.ping();
        _log('Terhubung ke host: ${pingRes["service"]} (Disk free: ${(pingRes["disk"]?["free_bytes"] ?? 0) ~/ (1024 * 1024 * 1024)} GB)');
      } catch (e) {
        _log('Gagal menghubungi host: $e');
        _state = _state.copyWith(
          isSyncing: false,
          statusMessage: 'Host offline atau URL salah',
        );
        notifyListeners();
        return;
      }

      final deviceId = await _getDeviceId();

      // 1. Scan gallery
      _state = _state.copyWith(statusMessage: 'Memindai foto & video lokal...');
      notifyListeners();
      final scannedAssets = await scannerService.scanForUnsyncedAssets(
        maxAssets: 500,
        onProgress: (cur, tot) {
          _state = _state.copyWith(statusMessage: 'Memindai galeri: $cur/$tot');
          notifyListeners();
        },
      );

      if (scannedAssets.isEmpty) {
        _log('Semua aset galeri sudah sinkron dengan server!');
        _state = _state.copyWith(
          isSyncing: false,
          statusMessage: 'Semua foto sudah tercadangkan',
        );
        notifyListeners();
        return;
      }

      _log('Ditemukan ${scannedAssets.length} aset baru untuk dicek.');

      // 2. Pre-flight Check in batches of 50
      final List<LocalScannedAsset> assetsToUpload = [];
      int preflightSkipped = 0;
      const int batchSize = 50;

      for (int i = 0; i < scannedAssets.length; i += batchSize) {
        if (_cancelRequested) break;

        final end = (i + batchSize < scannedAssets.length) ? i + batchSize : scannedAssets.length;
        final batch = scannedAssets.sublist(i, end);
        final hashes = batch.map((a) => a.hash).toList();

        _state = _state.copyWith(
          statusMessage: 'Preflight check: batch ${(i ~/ batchSize) + 1}...',
        );
        notifyListeners();

        try {
          final missingHashes = await apiClient.preflight(
            deviceId: deviceId,
            hashes: hashes,
          );

          final missingSet = missingHashes.toSet();

          for (final asset in batch) {
            if (missingSet.contains(asset.hash)) {
              assetsToUpload.add(asset);
            } else {
              // Server already has this hash -> mark synced locally immediately!
              await localDb.markSynced(asset.hash, 0);
              await localDb.markSyncedByAssetId(asset.entity.id, serverId: 0);
              preflightSkipped++;
            }
          }
        } catch (e) {
          _log('Error preflight batch: $e. Memasukkan semua ke antrean upload.');
          assetsToUpload.addAll(batch);
        }
      }

      _log('Preflight selesai: ${assetsToUpload.length} perlu diunggah, $preflightSkipped sudah ada di server.');

      if (assetsToUpload.isEmpty) {
        _state = _state.copyWith(
          isSyncing: false,
          statusMessage: 'Semua file sudah ada di server (Deduplikasi kilat)',
          skippedCount: preflightSkipped,
        );
        notifyListeners();
        return;
      }

      // 3. Upload missing files
      int uploaded = 0;
      int errors = 0;

      _state = _state.copyWith(
        totalToUpload: assetsToUpload.length,
        skippedCount: preflightSkipped,
      );

      for (int i = 0; i < assetsToUpload.length; i++) {
        if (_cancelRequested) {
          _log('Sinkronisasi dihentikan oleh pengguna.');
          break;
        }

        final item = assetsToUpload[i];
        final fileName = item.entity.title ?? item.file.path.split(Platform.pathSeparator).last;

        _state = _state.copyWith(
          currentFileName: fileName,
          currentProgress: 0.0,
          statusMessage: 'Mengunggah (${i + 1}/${assetsToUpload.length}): $fileName',
        );
        notifyListeners();

        File? thumbFile;
        try {
          final thumbBytes = await item.entity.thumbnailDataWithSize(
            const ThumbnailSize(500, 500),
            quality: 85,
          );
          if (thumbBytes != null && thumbBytes.isNotEmpty) {
            final tempDir = await getTemporaryDirectory();
            final tFile = File('${tempDir.path}/thumb_${item.hash}.jpg');
            await tFile.writeAsBytes(thumbBytes);
            thumbFile = tFile;
          }
        } catch (_) {}

        try {
          final uploadRes = await apiClient.upload(
            file: item.file,
            deviceId: deviceId,
            clientHash: item.hash,
            takenAt: item.entity.createDateTime,
            width: item.entity.width > 0 ? item.entity.width : null,
            height: item.entity.height > 0 ? item.entity.height : null,
            duration: item.entity.type == AssetType.video && item.entity.duration > 0
                ? item.entity.duration.toDouble()
                : null,
            thumbnailFile: thumbFile,
            onSendProgress: (sent, total) {
              if (total > 0) {
                final double p = sent / total;
                _state = _state.copyWith(currentProgress: p);
                notifyListeners();
              }
            },
          );

          final mediaInfo = uploadRes['media'] as Map<String, dynamic>?;
          final int serverId = (mediaInfo?['id'] as int?) ?? 0;

          await localDb.markSynced(item.hash, serverId);
          await localDb.markSyncedByAssetId(item.entity.id, serverId: serverId);
          uploaded++;
          _log('Sukses mencadangkan: $fileName');

          _state = _state.copyWith(
            uploadedCount: uploaded,
            currentProgress: 1.0,
          );
          notifyListeners();
        } catch (e) {
          errors++;
          _log('Gagal mengunggah $fileName: $e');
          await localDb.markFailed(item.entity.id, e.toString());
          _state = _state.copyWith(errorCount: errors);
          notifyListeners();
        } finally {
          if (thumbFile != null && await thumbFile.exists()) {
            try {
              await thumbFile.delete();
            } catch (_) {}
          }
        }
      }

      _state = _state.copyWith(
        isSyncing: false,
        statusMessage: _cancelRequested
            ? 'Sinkronisasi dibatalkan'
            : 'Selesai: $uploaded terunggah, $errors gagal, $preflightSkipped dilewati',
      );
      notifyListeners();
    } catch (e) {
      _log('Fatal sync error: $e');
      _state = _state.copyWith(
        isSyncing: false,
        statusMessage: 'Error: $e',
      );
      notifyListeners();
    } finally {
      await BackgroundTaskManager.setKeepScreenOn(false);
      await BackgroundTaskManager.endBackgroundTask();
    }
  }
}
