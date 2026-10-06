import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/database/local_database.dart';
import '../../core/models/gallery_media_item.dart';
import '../../core/models/media_item.dart';
import '../../core/network/api_client.dart';
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

  GalleryViewMode get viewMode => _viewMode;
  GalleryFilter get currentFilter => _currentFilter;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasPermission => _hasPermission;
  String get serverBaseUrl => _apiClient.baseUrl;

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

      final res = await _apiClient.getMediaTimeline(type: typeParam);
      final groupsData = res['groups'] as List<dynamic>? ?? [];
      final int serverTotal = (res['total_media'] as num?)?.toInt() ?? 0;

      final List<GalleryMediaItem> items = [];

      for (final g in groupsData) {
        if (g is Map<String, dynamic>) {
          final itemsRaw = g['items'] as List<dynamic>? ?? [];
          for (final raw in itemsRaw) {
            if (raw is Map<String, dynamic>) {
              final mediaItem = MediaItem.fromJson(raw);
              items.add(GalleryMediaItem.fromServerItem(mediaItem));
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
      final String deviceId = Platform.localHostname.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

      final uploadRes = await _apiClient.upload(
        file: file,
        deviceId: deviceId,
        clientHash: hash,
        takenAt: item.createDateTime,
      );

      final mediaInfo = uploadRes['media'] as Map<String, dynamic>?;
      final int serverId = (mediaInfo?['id'] as int?) ?? 0;

      await _localDb.markSynced(hash, serverId);
      await _localDb.markSyncedByAssetId(item.id, serverId: serverId);

      // Update in-memory item state to backed up (green checkmark)
      final idx = _deviceMedia.indexWhere((m) => m.id == item.id);
      if (idx != -1) {
        _deviceMedia[idx] = _deviceMedia[idx].copyWith(isSynced: true, hash: hash);
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
