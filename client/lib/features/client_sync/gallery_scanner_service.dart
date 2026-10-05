import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/database/asset_sync_entity.dart';
import '../../core/database/local_database.dart';
import 'smart_hasher.dart';

class LocalScannedAsset {
  final AssetEntity entity;
  final File file;
  final String hash;
  final int fileSize;
  final bool isVideo;

  LocalScannedAsset({
    required this.entity,
    required this.file,
    required this.hash,
    required this.fileSize,
    required this.isVideo,
  });
}

class GalleryScannerService extends ChangeNotifier {
  final LocalDatabase _localDb = LocalDatabase.instance;
  bool _isScanning = false;
  int _scannedTotal = 0;
  int _alreadySyncedCount = 0;
  int _newAssetsFoundCount = 0;

  bool get isScanning => _isScanning;
  int get scannedTotal => _scannedTotal;
  int get alreadySyncedCount => _alreadySyncedCount;
  int get newAssetsFoundCount => _newAssetsFoundCount;

  /// Requests media permissions on Android/iOS/macOS
  Future<bool> requestPermission() async {
    final PermissionState state = await PhotoManager.requestPermissionExtend();
    return state.isAuth || state.hasAccess;
  }

  /// Scans gallery and extracts candidates that are not yet synced
  Future<List<LocalScannedAsset>> scanForUnsyncedAssets({
    int maxAssets = 500,
    void Function(int current, int total)? onProgress,
  }) async {
    _isScanning = true;
    _scannedTotal = 0;
    _alreadySyncedCount = 0;
    _newAssetsFoundCount = 0;
    notifyListeners();

    final List<LocalScannedAsset> pendingSyncList = [];

    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.common, // Photos + Videos
      );

      if (albums.isEmpty) {
        _isScanning = false;
        notifyListeners();
        return [];
      }

      final AssetPathEntity recentAlbum = albums.first;
      final int totalCount = await recentAlbum.assetCountAsync;
      final int fetchLimit = totalCount > maxAssets ? maxAssets : totalCount;

      const int pageSize = 50;
      int page = 0;

      while (page * pageSize < fetchLimit) {
        final List<AssetEntity> pageAssets = await recentAlbum.getAssetListPaged(
          page: page,
          size: pageSize,
        );

        if (pageAssets.isEmpty) break;

        for (final asset in pageAssets) {
          _scannedTotal++;
          if (onProgress != null) {
            onProgress(_scannedTotal, fetchLimit);
          }

          // 1. Quick check local database by asset ID
          final bool isSynced = await _localDb.isAssetSynced(asset.id);
          if (isSynced) {
            _alreadySyncedCount++;
            continue;
          }

          // 2. Fetch underlying file
          final File? assetFile = await asset.originFile;
          if (assetFile == null || !await assetFile.exists()) {
            continue;
          }

          final int size = await assetFile.length();
          final bool isVideo = asset.type == AssetType.video;

          // 3. Compute Smart Hash
          final String hash = await SmartHasher.computeHash(assetFile, isVideo: isVideo);

          // 4. Double check database by hash (anti-duplication)
          final existing = await _localDb.getByHash(hash);
          if (existing != null && existing.status == SyncStatus.synced) {
            _alreadySyncedCount++;
            continue;
          }

          // Register in local database as pending
          final entityRecord = AssetSyncEntity(
            assetId: asset.id,
            hash: hash,
            fileName: asset.title ?? assetFile.path.split(Platform.pathSeparator).last,
            filePath: assetFile.path,
            fileSize: size,
            mimeType: asset.mimeType ?? (isVideo ? 'video/mp4' : 'image/jpeg'),
            status: SyncStatus.pending,
            createdAt: asset.createDateTime,
          );
          await _localDb.insertOrUpdate(entityRecord);

          pendingSyncList.add(LocalScannedAsset(
            entity: asset,
            file: assetFile,
            hash: hash,
            fileSize: size,
            isVideo: isVideo,
          ));

          _newAssetsFoundCount++;
          notifyListeners();
        }

        page++;
      }
    } catch (e) {
      debugPrint('[GalleryScannerService] Scan error: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }

    return pendingSyncList;
  }
}
