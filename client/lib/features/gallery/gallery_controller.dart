import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/database/local_database.dart';
import '../../core/models/gallery_media_item.dart';
import '../../core/models/media_item.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/device_identity.dart';
import '../client_sync/smart_hasher.dart';

enum GalleryViewMode { device, server }
enum GalleryFilter { all, unsynced, synced, photos, videos }

class TimelineDateGroup {
  final String title;
  final DateTime date;
  final List<GalleryMediaItem> items;

  TimelineDateGroup({
    required this.title,
    required this.date,
    required this.items,
  });
}

class GalleryController extends ChangeNotifier {
  final ApiClient _apiClient;
  final LocalDatabase _localDb = LocalDatabase.instance;

  GalleryViewMode _viewMode = GalleryViewMode.device;
  GalleryFilter _currentFilter = GalleryFilter.all;
  String _searchQuery = '';

  bool _isLoading = false;
  String? _errorMessage;
  bool _hasPermission = true;

  // Separate states for Device Gallery vs Server Gallery
  List<GalleryMediaItem> _deviceMedia = [];
  List<TimelineDateGroup> _deviceTimelineGroups = [];
  int _deviceTotalCount = 0;
  int _deviceSyncedCount = 0;
  int _deviceUnsyncedCount = 0;

  List<GalleryMediaItem> _serverMedia = [];
  List<TimelineDateGroup> _serverTimelineGroups = [];
  int _serverTotalCount = 0;
  List<Map<String, dynamic>> _serverDevices = [];
  String? _selectedDeviceId;

  GalleryViewMode get viewMode => _viewMode;
  GalleryFilter get currentFilter => _currentFilter;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasPermission => _hasPermission;
  String get serverBaseUrl => _apiClient.baseUrl;
  List<Map<String, dynamic>> get serverDevices => _serverDevices;
  String? get selectedDeviceId => _selectedDeviceId;

  List<GalleryMediaItem> get allMedia =>
      _viewMode == GalleryViewMode.device ? _deviceMedia : _serverMedia;

  List<TimelineDateGroup> get timelineGroups =>
      _viewMode == GalleryViewMode.device ? _deviceTimelineGroups : _serverTimelineGroups;

  int get totalCount =>
      _viewMode == GalleryViewMode.device ? _deviceTotalCount : _serverTotalCount;

  int get syncedCount =>
      _viewMode == GalleryViewMode.device ? _deviceSyncedCount : _serverTotalCount;

  int get unsyncedCount =>
      _viewMode == GalleryViewMode.device ? _deviceUnsyncedCount : 0;

  GalleryController(this._apiClient);

  void setSelectedDevice(String? deviceId) {
    if (_selectedDeviceId == deviceId) return;
    _selectedDeviceId = deviceId;
    notifyListeners();
    if (_viewMode == GalleryViewMode.server) {
      _fetchServerGallery();
    }
  }

  void setViewMode(GalleryViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    _currentFilter = GalleryFilter.all;
    _searchQuery = '';
    _errorMessage = null;
    notifyListeners();
    fetchGallery();
  }

  void setFilter(GalleryFilter filter) {
    if (_currentFilter == filter) return;
    _currentFilter = filter;
    _rebuildTimeline();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    _rebuildTimeline();
    notifyListeners();
  }

  /// Main entry point to load gallery depending on current view mode
  Future<void> fetchGallery() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    if (_viewMode == GalleryViewMode.device) {
      await _fetchDeviceGallery();
    } else {
      await _fetchServerGallery();
    }
  }

  /// Fetches local device photos and cross-references backup status with SQLite
  Future<void> _fetchDeviceGallery() async {
    try {
      final PermissionState state = await PhotoManager.requestPermissionExtend();
      _hasPermission = state.isAuth || state.hasAccess;

      if (!_hasPermission) {
        _isLoading = false;
        _errorMessage = 'Izin akses galeri perangkat ditolak. Mohon izinkan akses foto di Pengaturan iOS/Android.';
        _deviceMedia = [];
        _deviceTimelineGroups = [];
        notifyListeners();
        return;
      }

      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.common, // Image + Video
      );

      if (albums.isEmpty) {
        _isLoading = false;
        _deviceMedia = [];
        _deviceTimelineGroups = [];
        _deviceTotalCount = 0;
        _deviceSyncedCount = 0;
        _deviceUnsyncedCount = 0;
        notifyListeners();
        return;
      }

      final recentAlbum = albums.first;
      final int count = await recentAlbum.assetCountAsync;
      final int fetchLimit = count > 1000 ? 1000 : count;

      final List<AssetEntity> rawAssets = await recentAlbum.getAssetListPaged(
        page: 0,
        size: fetchLimit,
      );

      // Fetch all synced IDs from local database
      final syncedAssetIds = await _localDb.getAllSyncedAssetIds();

      int synced = 0;
      int unsynced = 0;
      final List<GalleryMediaItem> items = [];

      for (final asset in rawAssets) {
        final bool isSynced = syncedAssetIds.contains(asset.id);
        if (isSynced) {
          synced++;
        } else {
          unsynced++;
        }

        items.add(GalleryMediaItem.fromAssetEntity(
          asset,
          isSynced: isSynced,
        ));
      }

      _deviceMedia = items;
      _deviceTotalCount = items.length;
      _deviceSyncedCount = synced;
      _deviceUnsyncedCount = unsynced;
      _rebuildDeviceTimeline();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Gagal memuat galeri perangkat: $e';
      notifyListeners();
    }
  }

  /// Fetches media stored on the Go server
  Future<void> _fetchServerGallery() async {
    try {
      String? typeParam;
      if (_currentFilter == GalleryFilter.photos) typeParam = 'image';
      if (_currentFilter == GalleryFilter.videos) typeParam = 'video';

      // 1. Fetch connected/registered devices from server API
      try {
        _serverDevices = await _apiClient.getDevices();
      } catch (e) {
        debugPrint('[GalleryController] getDevices API failed: $e');
      }

      // 2. Fetch timeline filtered by deviceId if set
      final res = await _apiClient.getMediaTimeline(
        type: typeParam,
        deviceId: _selectedDeviceId,
      );
      final groupsData = res['groups'] as List<dynamic>? ?? [];
      final int serverTotal = (res['total_media'] as num?)?.toInt() ?? 0;

      // 3. Dynamically discover devices from timeline items if server API returned empty
      final Map<String, int> dynamicDevCounts = {};
      for (final g in groupsData) {
        if (g is Map<String, dynamic>) {
          final itemsRaw = g['items'] as List<dynamic>? ?? [];
          for (final raw in itemsRaw) {
            if (raw is Map<String, dynamic>) {
              final dId = raw['device_id']?.toString().trim() ?? '';
              if (dId.isNotEmpty) {
                dynamicDevCounts[dId] = (dynamicDevCounts[dId] ?? 0) + 1;
              }
            }
          }
        }
      }

      if (_serverDevices.isEmpty && dynamicDevCounts.isNotEmpty) {
        _serverDevices = dynamicDevCounts.entries.map((e) => {
          'device_id': e.key,
          'total_media': e.value,
        }).toList();
      } else if (dynamicDevCounts.isNotEmpty) {
        final existing = _serverDevices.map((d) => d['device_id']?.toString() ?? '').toSet();
        for (final entry in dynamicDevCounts.entries) {
          if (!existing.contains(entry.key)) {
            _serverDevices.add({
              'device_id': entry.key,
              'total_media': entry.value,
            });
          }
        }
      }

      // 3. Multi-strategy local asset resolution
      final assetIdByServerId = await _localDb.getServerIdToAssetIdMap();
      final Map<String, AssetEntity> localByAssetId = {
        for (final m in _deviceMedia)
          if (m.localEntity != null) m.id: m.localEntity!
      };
      final Map<String, AssetEntity> localByTitle = {
        for (final m in _deviceMedia)
          if (m.localEntity != null) m.title.toLowerCase(): m.localEntity!
      };
      final Map<String, AssetEntity> localByHash = {
        for (final m in _deviceMedia)
          if (m.localEntity != null && m.hash != null) m.hash!: m.localEntity!
      };

      final List<GalleryMediaItem> items = [];

      for (final g in groupsData) {
        if (g is Map<String, dynamic>) {
          final itemsRaw = g['items'] as List<dynamic>? ?? [];
          for (final raw in itemsRaw) {
            if (raw is Map<String, dynamic>) {
              final mediaItem = MediaItem.fromJson(raw);

              // Strategy A: Direct SQLite server_id -> asset_id link
              final matchedAssetId = assetIdByServerId[mediaItem.id];
              AssetEntity? entity = matchedAssetId != null ? localByAssetId[matchedAssetId] : null;

              // Strategy B: Hash match
              if (entity == null && mediaItem.hash.isNotEmpty) {
                entity = localByHash[mediaItem.hash];
              }

              // Strategy C: Exact or stripped title match
              if (entity == null) {
                final fn = mediaItem.fileName.toLowerCase();
                entity = localByTitle[fn];
                if (entity == null && fn.contains('.')) {
                  final withoutExt = fn.substring(0, fn.lastIndexOf('.'));
                  entity = localByTitle[withoutExt];
                }
              }

              // Strategy D: Video duration and taken timestamp match
              if (entity == null && mediaItem.isVideo && mediaItem.duration > 0) {
                for (final m in _deviceMedia) {
                  if (m.isVideo && m.localEntity != null) {
                    final durDiff = (m.videoDuration.inSeconds - mediaItem.duration.round()).abs();
                    if (durDiff <= 1) {
                      if (mediaItem.takenAt != null) {
                        final timeDiff = (m.createDateTime.difference(mediaItem.takenAt!).inSeconds).abs();
                        if (timeDiff <= 5) {
                          entity = m.localEntity;
                          break;
                        }
                      } else {
                        entity = m.localEntity;
                        break;
                      }
                    }
                  }
                }
              }

              items.add(GalleryMediaItem.fromServerItem(mediaItem).copyWith(localEntity: entity));
            }
          }
        }
      }

      _serverMedia = items;
      _serverTotalCount = serverTotal;
      _rebuildServerTimeline();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _serverMedia = [];
      _serverTimelineGroups = [];
      _serverTotalCount = 0;
      _errorMessage = 'Tidak dapat terhubung ke server (${_apiClient.baseUrl}). Pastikan host server menyala di jaringan Wi-Fi lokal.';
      notifyListeners();
    }
  }

  /// Quickly refreshes sync status without re-scanning all assets from OS
  Future<void> refreshSyncStatus() async {
    try {
      final syncedAssetIds = await _localDb.getAllSyncedAssetIds();
      int synced = 0;
      int unsynced = 0;

      final updated = _deviceMedia.map((m) {
        final isSynced = syncedAssetIds.contains(m.id);
        if (isSynced) {
          synced++;
        } else {
          unsynced++;
        }
        return m.copyWith(isSynced: isSynced);
      }).toList();

      _deviceMedia = updated;
      _deviceSyncedCount = synced;
      _deviceUnsyncedCount = unsynced;
      _rebuildDeviceTimeline();
      notifyListeners();
    } catch (_) {}
  }

  /// Backs up a single local media item directly to the server
  Future<bool> backupSingleAsset(GalleryMediaItem item) async {
    if (item.isSynced || item.localEntity == null) return true;

    try {
      final File? file = await item.localEntity!.originFile ?? await item.localEntity!.file;
      if (file == null || !await file.exists()) return false;

      final String hash = await SmartHasher.computeHash(file, isVideo: item.isVideo);
      final String deviceId = await DeviceIdentity.getDeviceId();

      File? thumbFile;
      if (item.isVideo) {
        try {
          final thumbBytes = await item.localEntity!.thumbnailDataWithSize(const ThumbnailSize(400, 400));
          if (thumbBytes != null && thumbBytes.isNotEmpty) {
            final tempDir = Directory.systemTemp;
            thumbFile = File('${tempDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await thumbFile.writeAsBytes(thumbBytes);
          }
        } catch (thumbErr) {
          debugPrint('[GalleryController] Failed to generate video thumb: $thumbErr');
        }
      }

      Map<String, dynamic> uploadRes;
      try {
        uploadRes = await _apiClient.upload(
          file: file,
          deviceId: deviceId,
          clientHash: hash,
          takenAt: item.createDateTime,
          thumbnailFile: thumbFile,
        );
      } finally {
        if (thumbFile != null && await thumbFile.exists()) {
          try {
            await thumbFile.delete();
          } catch (_) {}
        }
      }

      final mediaInfo = uploadRes['media'] as Map<String, dynamic>?;
      final int serverId = (mediaInfo?['id'] as int?) ?? 0;
      final String finalHash = (mediaInfo?['hash'] as String?) ?? hash;

      await _localDb.markSynced(finalHash, serverId);
      await _localDb.markSyncedByAssetId(item.id, serverId: serverId, hash: finalHash);

      // Update in-memory item state to backed up (green checkmark)
      final idx = _deviceMedia.indexWhere((m) => m.id == item.id);
      if (idx != -1) {
        _deviceMedia[idx] = _deviceMedia[idx].copyWith(isSynced: true, hash: finalHash);
        _deviceSyncedCount++;
        if (_deviceUnsyncedCount > 0) _deviceUnsyncedCount--;
        _rebuildDeviceTimeline();
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('[GalleryController] Backup single asset error: $e');
      return false;
    }
  }

  /// Backs up a batch of selected items with progress callbacks
  Future<int> backupSelectedAssets(
    List<GalleryMediaItem> items, {
    void Function(int current, int total, String title)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final toBackup = items.where((i) => !i.isSynced && i.localEntity != null).toList();
    if (toBackup.isEmpty) return 0;

    int successCount = 0;
    final total = toBackup.length;

    for (int i = 0; i < total; i++) {
      if (isCancelled != null && isCancelled()) break;

      final item = toBackup[i];
      onProgress?.call(i + 1, total, item.title);

      final ok = await backupSingleAsset(item);
      if (ok) {
        successCount++;
      }
    }

    return successCount;
  }


  void _rebuildTimeline() {
    if (_viewMode == GalleryViewMode.device) {
      _rebuildDeviceTimeline();
    } else {
      _rebuildServerTimeline();
    }
  }

  void _rebuildDeviceTimeline() {
    List<GalleryMediaItem> filtered = _deviceMedia;

    if (_currentFilter == GalleryFilter.unsynced) {
      filtered = filtered.where((m) => !m.isSynced).toList();
    } else if (_currentFilter == GalleryFilter.synced) {
      filtered = filtered.where((m) => m.isSynced).toList();
    } else if (_currentFilter == GalleryFilter.photos) {
      filtered = filtered.where((m) => !m.isVideo).toList();
    } else if (_currentFilter == GalleryFilter.videos) {
      filtered = filtered.where((m) => m.isVideo).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((m) => m.title.toLowerCase().contains(_searchQuery)).toList();
    }

    final Map<String, List<GalleryMediaItem>> map = {};
    for (final item in filtered) {
      final key = item.dateGroupKey;
      map.putIfAbsent(key, () => []).add(item);
    }

    _deviceTimelineGroups = map.entries.map((e) {
      return TimelineDateGroup(
        title: e.key,
        date: e.value.first.createDateTime,
        items: e.value,
      );
    }).toList();
  }

  void _rebuildServerTimeline() {
    List<GalleryMediaItem> filtered = _serverMedia;

    if (_currentFilter == GalleryFilter.photos) {
      filtered = filtered.where((m) => !m.isVideo).toList();
    } else if (_currentFilter == GalleryFilter.videos) {
      filtered = filtered.where((m) => m.isVideo).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((m) => m.title.toLowerCase().contains(_searchQuery)).toList();
    }

    final Map<String, List<GalleryMediaItem>> map = {};
    for (final item in filtered) {
      final key = item.dateGroupKey;
      map.putIfAbsent(key, () => []).add(item);
    }

    _serverTimelineGroups = map.entries.map((e) {
      return TimelineDateGroup(
        title: e.key,
        date: e.value.first.createDateTime,
        items: e.value,
      );
    }).toList();
  }
}
