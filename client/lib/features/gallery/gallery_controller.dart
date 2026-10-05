import 'package:flutter/foundation.dart';
import '../../core/models/media_item.dart';
import '../../core/network/api_client.dart';

enum GalleryFilter { all, photos, videos, favorites }
enum GallerySource { server, local }

class TimelineDateGroup {
  final String title;
  final String dateStr;
  final List<MediaItem> items;

  TimelineDateGroup({
    required this.title,
    required this.dateStr,
    required this.items,
  });
}

class GalleryController extends ChangeNotifier {
  final ApiClient _apiClient;
  bool _isLoading = false;
  String? _errorMessage;
  List<MediaItem> _allMedia = [];
  List<TimelineDateGroup> _timelineGroups = [];
  GalleryFilter _currentFilter = GalleryFilter.all;
  String _searchQuery = '';
  int _totalServerCount = 0;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<MediaItem> get allMedia => _allMedia;
  List<TimelineDateGroup> get timelineGroups => _timelineGroups;
  GalleryFilter get currentFilter => _currentFilter;
  String get searchQuery => _searchQuery;
  int get totalServerCount => _totalServerCount;
  String get serverBaseUrl => _apiClient.baseUrl;

  GalleryController(this._apiClient);

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

  /// Fetches media from the server and builds timeline groups
  Future<void> fetchGallery() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      String? typeParam;
      if (_currentFilter == GalleryFilter.photos) typeParam = 'image';
      if (_currentFilter == GalleryFilter.videos) typeParam = 'video';
      bool? favParam = _currentFilter == GalleryFilter.favorites ? true : null;

      final res = await _apiClient.getMediaTimeline(
        type: typeParam,
        favorite: favParam,
      );

      final groupsData = res['groups'] as List<dynamic>? ?? [];
      _totalServerCount = (res['total_media'] as num?)?.toInt() ?? 0;

      final List<MediaItem> loadedMedia = [];
      final List<TimelineDateGroup> groups = [];

      for (final g in groupsData) {
        if (g is Map<String, dynamic>) {
          final dateStr = g['date']?.toString() ?? '';
          final itemsRaw = g['items'] as List<dynamic>? ?? [];
          final items = itemsRaw
              .whereType<Map<String, dynamic>>()
              .map((e) => MediaItem.fromJson(e))
              .toList();

          if (items.isNotEmpty) {
            loadedMedia.addAll(items);
            groups.add(TimelineDateGroup(
              title: items.first.dateGroupKey,
              dateStr: dateStr,
              items: items,
            ));
          }
        }
      }

      _allMedia = loadedMedia;
      _timelineGroups = groups;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Gagal memuat galeri dari server: $e';
      notifyListeners();
    }
  }

  void _rebuildTimeline() {
    List<MediaItem> filtered = _allMedia;

    if (_currentFilter == GalleryFilter.photos) {
      filtered = filtered.where((m) => !m.isVideo).toList();
    } else if (_currentFilter == GalleryFilter.videos) {
      filtered = filtered.where((m) => m.isVideo).toList();
    } else if (_currentFilter == GalleryFilter.favorites) {
      filtered = filtered.where((m) => m.isFavorite).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((m) => m.fileName.toLowerCase().contains(_searchQuery)).toList();
    }

    // Regroup by dateGroupKey
    final Map<String, List<MediaItem>> map = {};
    for (final item in filtered) {
      final key = item.dateGroupKey;
      map.putIfAbsent(key, () => []).add(item);
    }

    _timelineGroups = map.entries.map((e) {
      return TimelineDateGroup(
        title: e.key,
        dateStr: e.value.first.displayDate.toIso8601String(),
        items: e.value,
      );
    }).toList();
  }

  /// Toggles favorite status locally and on server
  Future<void> toggleFavorite(MediaItem item) async {
    final newStatus = !item.isFavorite;
    // Optimistic UI update
    _updateItemInList(item.copyWith(isFavorite: newStatus));

    try {
      await _apiClient.toggleFavorite(item.id);
    } catch (_) {
      // Revert on failure
      _updateItemInList(item);
    }
  }

  /// Deletes media locally and on server
  Future<bool> deleteMedia(MediaItem item) async {
    try {
      final success = await _apiClient.deleteMedia(item.id);
      if (success) {
        _allMedia.removeWhere((m) => m.id == item.id);
        _rebuildTimeline();
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _updateItemInList(MediaItem updated) {
    final idx = _allMedia.indexWhere((m) => m.id == updated.id);
    if (idx != -1) {
      _allMedia[idx] = updated;
      _rebuildTimeline();
      notifyListeners();
    }
  }
}
