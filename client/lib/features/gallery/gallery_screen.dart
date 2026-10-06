import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../../core/models/gallery_media_item.dart';
import 'gallery_controller.dart';
import 'media_viewer_screen.dart';

class GalleryScreen extends StatefulWidget {
  final GalleryController controller;
  final VoidCallback? onNavigateToSync;

  const GalleryScreen({
    super.key,
    required this.controller,
    this.onNavigateToSync,
  });

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();

  // Selection mode states
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  // Batch backup state
  bool _isBatchBackingUp = false;
  int _batchCurrent = 0;
  int _batchTotal = 0;
  String _batchCurrentTitle = '';
  bool _cancelBatchRequested = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    widget.controller.fetchGallery();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _enterSelectionMode({String? initialSelectedId}) {
    HapticFeedback.selectionClick();
    setState(() {
      _isSelectionMode = true;
      if (initialSelectedId != null) {
        _selectedIds.add(initialSelectedId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleItemSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<GalleryMediaItem> items) {
    HapticFeedback.lightImpact();
    setState(() {
      for (final item in items) {
        _selectedIds.add(item.id);
      }
    });
  }

  void _deselectAll() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedIds.clear();
    });
  }

  void _toggleGroupSelection(TimelineDateGroup group) {
    HapticFeedback.lightImpact();
    final groupIds = group.items.map((i) => i.id).toSet();
    final allSelected = groupIds.isNotEmpty && groupIds.every((id) => _selectedIds.contains(id));
    setState(() {
      if (!_isSelectionMode) _isSelectionMode = true;
      if (allSelected) {
        _selectedIds.removeAll(groupIds);
      } else {
        _selectedIds.addAll(groupIds);
      }
    });
  }

  Future<void> _startBatchBackup(List<GalleryMediaItem> itemsToBackup) async {
    if (itemsToBackup.isEmpty || _isBatchBackingUp) return;

    setState(() {
      _isBatchBackingUp = true;
      _batchCurrent = 0;
      _batchTotal = itemsToBackup.length;
      _batchCurrentTitle = itemsToBackup.first.title;
      _cancelBatchRequested = false;
    });

    bool dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final progress = _batchTotal > 0 ? (_batchCurrent / _batchTotal) : 0.0;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.cloud_upload_rounded, color: Colors.blueAccent),
                SizedBox(width: 10),
                Text('Mencadangkan Media', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$_batchCurrent dari $_batchTotal media',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _batchCurrentTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _cancelBatchRequested = true;
                  if (dialogOpen) {
                    dialogOpen = false;
                    Navigator.of(dlgCtx).pop();
                  }
                },
                child: const Text('Batal'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      dialogOpen = false;
    });

    int successCount = 0;
    try {
      successCount = await widget.controller.backupSelectedAssets(
        itemsToBackup,
        onProgress: (current, total, title) {
          if (mounted) {
            setState(() {
              _batchCurrent = current;
              _batchTotal = total;
              _batchCurrentTitle = title;
            });
          }
        },
        isCancelled: () => _cancelBatchRequested,
      );
    } finally {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (mounted) {
        setState(() {
          _isBatchBackingUp = false;
        });

        // Remove successfully synced IDs from selection
        final successfulIds = itemsToBackup.map((i) => i.id).toSet();
        setState(() {
          _selectedIds.removeAll(successfulIds);
          if (_selectedIds.isEmpty) {
            _isSelectionMode = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selesai! $successCount dari ${itemsToBackup.length} media berhasil dicadangkan ke server.',
            ),
            backgroundColor: const Color(0xFF16A34A),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = widget.controller;

    // Collect all visible items across current timeline groups
    final List<GalleryMediaItem> visibleItems = [];
    for (final group in ctrl.timelineGroups) {
      visibleItems.addAll(group.items);
    }

    final bool allVisibleSelected = visibleItems.isNotEmpty &&
        visibleItems.every((item) => _selectedIds.contains(item.id));

    return Scaffold(
      appBar: _isSelectionMode
          ? AppBar(
              leading: IconButton(
                tooltip: 'Batal',
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitSelectionMode,
              ),
              title: Text(
                '${_selectedIds.length} Dipilih',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                if (visibleItems.isNotEmpty)
                  TextButton(
                    onPressed: allVisibleSelected
                        ? _deselectAll
                        : () => _selectAll(visibleItems),
                    child: Text(
                      allVisibleSelected ? 'Batal Semua' : 'Pilih Semua',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                TextButton(
                  onPressed: _exitSelectionMode,
                  child: const Text('Selesai', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: _buildFilterBar(theme, ctrl),
              ),
            )
          : AppBar(
              title: _isSearching
                  ? TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Cari foto atau video...',
                        border: InputBorder.none,
                      ),
                      onChanged: ctrl.setSearchQuery,
                    )
                  : Row(
                      children: [
                        Icon(
                          ctrl.viewMode == GalleryViewMode.device
                              ? Icons.phone_iphone_rounded
                              : Icons.dns_rounded,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          ctrl.viewMode == GalleryViewMode.device ? 'Galeri iPhone' : 'Galeri Server',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
              actions: [
                if (!_isSearching && visibleItems.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _enterSelectionMode(),
                    icon: const Icon(Icons.checklist_rounded, size: 18),
                    label: const Text('Pilih', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                IconButton(
                  tooltip: _isSearching ? 'Tutup Pencarian' : 'Cari Media',
                  icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) {
                        _searchCtrl.clear();
                        ctrl.setSearchQuery('');
                      }
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Segarkan',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: ctrl.fetchGallery,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(96),
                child: Column(
                  children: [
                    // View Mode Selector (iPhone vs Server)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<GalleryViewMode>(
                          segments: const [
                            ButtonSegment(
                              value: GalleryViewMode.device,
                              label: Text('Galeri Perangkat'),
                              icon: Icon(Icons.phone_iphone_rounded, size: 16),
                            ),
                            ButtonSegment(
                              value: GalleryViewMode.server,
                              label: Text('Galeri Server'),
                              icon: Icon(Icons.cloud_done_rounded, size: 16),
                            ),
                          ],
                          selected: {ctrl.viewMode},
                          onSelectionChanged: (set) {
                            if (set.isNotEmpty) {
                              _exitSelectionMode();
                              ctrl.setViewMode(set.first);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Filter Chips Row
                    _buildFilterBar(theme, ctrl),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _isSelectionMode
          ? _buildSelectionBottomBar(theme, ctrl, visibleItems)
          : null,
      body: ctrl.isLoading && ctrl.timelineGroups.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ctrl.errorMessage != null && ctrl.timelineGroups.isEmpty
              ? _buildErrorView(theme, ctrl.errorMessage!)
              : ctrl.timelineGroups.isEmpty
                  ? _buildEmptyView(theme, ctrl)
                  : RefreshIndicator(
                      onRefresh: ctrl.fetchGallery,
                      child: CustomScrollView(
                        slivers: [
                          // Status Summary Card for Device Gallery
                          if (ctrl.viewMode == GalleryViewMode.device && !_isSelectionMode)
                            SliverToBoxAdapter(
                              child: _buildSyncStatusCard(theme, ctrl),
                            ),

                          // Timeline Groups
                          for (final group in ctrl.timelineGroups) ...[
                            SliverToBoxAdapter(
                              child: _buildDateHeader(theme, group),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              sliver: SliverGrid(
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 130,
                                  crossAxisSpacing: 3,
                                  mainAxisSpacing: 3,
                                  childAspectRatio: 1.0,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (ctx, index) {
                                    final item = group.items[index];
                                    return _buildMediaTile(ctx, item, visibleItems);
                                  },
                                  childCount: group.items.length,
                                ),
                              ),
                            ),
                            const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          ],
                          SliverToBoxAdapter(
                            child: SizedBox(height: _isSelectionMode ? 90 : 36),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildSyncStatusCard(ThemeData theme, GalleryController ctrl) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                // Synced counter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${ctrl.syncedCount} Terbackup',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Unsynced counter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFEA580C), size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${ctrl.unsyncedCount} Belum',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEA580C),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (ctrl.unsyncedCount > 0 && widget.onNavigateToSync != null)
            TextButton.icon(
              onPressed: widget.onNavigateToSync,
              icon: const Icon(Icons.cloud_upload_rounded, size: 16),
              label: const Text('Cadangkan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme, GalleryController ctrl) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildFilterChip('Semua (${ctrl.totalCount})', GalleryFilter.all, Icons.grid_view_rounded),
          if (ctrl.viewMode == GalleryViewMode.device) ...[
            const SizedBox(width: 8),
            _buildFilterChip(
              'Belum Backup (⚠️ ${ctrl.unsyncedCount})',
              GalleryFilter.unsynced,
              Icons.warning_amber_rounded,
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              'Sudah Backup (✅ ${ctrl.syncedCount})',
              GalleryFilter.synced,
              Icons.check_circle_outline_rounded,
            ),
          ],
          const SizedBox(width: 8),
          _buildFilterChip('Foto', GalleryFilter.photos, Icons.image_rounded),
          const SizedBox(width: 8),
          _buildFilterChip('Video', GalleryFilter.videos, Icons.videocam_rounded),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, GalleryFilter filter, IconData icon) {
    final isSelected = widget.controller.currentFilter == filter;
    return FilterChip(
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
      onSelected: (_) => widget.controller.setFilter(filter),
    );
  }

  Widget _buildDateHeader(ThemeData theme, TimelineDateGroup group) {
    final groupIds = group.items.map((i) => i.id).toSet();
    final bool allGroupSelected = groupIds.isNotEmpty && groupIds.every((id) => _selectedIds.contains(id));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                group.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${group.items.length})',
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            ),
            onPressed: () => _toggleGroupSelection(group),
            child: Text(
              _isSelectionMode
                  ? (allGroupSelected ? 'Batal' : 'Pilih')
                  : 'Pilih',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: (allGroupSelected && _isSelectionMode)
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTile(BuildContext context, GalleryMediaItem item, List<GalleryMediaItem> allItems) {
    final ctrl = widget.controller;
    final theme = Theme.of(context);
    final isSelected = _selectedIds.contains(item.id);

    return InkWell(
      onTap: () {
        if (_isSelectionMode) {
          _toggleItemSelection(item.id);
        } else {
          final initialIdx = allItems.indexWhere((m) => m.id == item.id);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MediaViewerScreen(
                items: allItems,
                initialIndex: initialIdx != -1 ? initialIdx : 0,
                controller: ctrl,
              ),
            ),
          );
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          _enterSelectionMode(initialSelectedId: item.id);
        } else {
          _toggleItemSelection(item.id);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail Image Surface
          ClipRRect(
            borderRadius: BorderRadius.circular(isSelected ? 6 : 0),
            child: item.isLocal && item.localEntity != null
                ? AssetEntityImage(
                    item.localEntity!,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize(250, 250),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                    ),
                  )
                : item.isServer && item.serverItem != null
                    ? Image.network(
                        item.serverItem!.thumbnailUrl(ctrl.serverBaseUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                        ),
                      )
                    : Container(color: Colors.grey.shade300),
          ),

          // Selection Overlay Tint & Border
          if (_isSelectionMode)
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary.withOpacity(0.28)
                      : Colors.transparent,
                  border: isSelected
                      ? Border.all(color: theme.colorScheme.primary, width: 3)
                      : null,
                  borderRadius: BorderRadius.circular(isSelected ? 6 : 0),
                ),
              ),
            ),

          // Selection Indicator Badge (Top Left)
          if (_isSelectionMode)
            Positioned(
              top: 5,
              left: 5,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? Colors.white : Colors.black.withOpacity(0.4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: isSelected
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: theme.colorScheme.primary,
                        size: 22,
                      )
                    : const Icon(
                        Icons.radio_button_unchecked_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
            ),

          // Video Duration Indicator (Bottom Left)
          if (item.isVideo)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      item.formattedDuration,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Backup Status Indicator (Top Right):
          // Green checkmark (centang) if synced, Amber/Orange exclamation (tanda seru) if unsynced
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: item.isSynced
                    ? const Color(0xFF16A34A).withOpacity(0.92) // Emerald green
                    : const Color(0xFFEA580C).withOpacity(0.95), // Amber/Orange warning
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                item.isSynced ? Icons.check_rounded : Icons.priority_high_rounded,
                size: 13,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBottomBar(
    ThemeData theme,
    GalleryController ctrl,
    List<GalleryMediaItem> visibleItems,
  ) {
    final selectedItems = visibleItems.where((i) => _selectedIds.contains(i.id)).toList();
    final unsyncedSelected = selectedItems.where((i) => !i.isSynced).toList();
    final isDevice = ctrl.viewMode == GalleryViewMode.device;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_selectedIds.length} Media Dipilih',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (isDevice)
                  Text(
                    unsyncedSelected.isNotEmpty
                        ? '${unsyncedSelected.length} belum dicadangkan'
                        : (_selectedIds.isNotEmpty ? 'Semua terpilih sudah dicadangkan' : 'Ketuk media untuk memilih'),
                    style: TextStyle(
                      fontSize: 12,
                      color: unsyncedSelected.isNotEmpty
                          ? const Color(0xFFEA580C)
                          : theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          if (isDevice && unsyncedSelected.isNotEmpty)
            FilledButton.icon(
              onPressed: _isBatchBackingUp
                  ? null
                  : () => _startBatchBackup(unsyncedSelected),
              icon: _isBatchBackingUp
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: Text(
                _isBatchBackingUp
                    ? '($_batchCurrent/$_batchTotal)'
                    : 'Cadangkan (${unsyncedSelected.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            )
          else if (_selectedIds.isNotEmpty)
            OutlinedButton(
              onPressed: _deselectAll,
              child: const Text('Batal Pilih'),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyView(ThemeData theme, GalleryController ctrl) {
    final isDevice = ctrl.viewMode == GalleryViewMode.device;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isDevice ? Icons.photo_library_outlined : Icons.cloud_off_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isDevice ? 'Tidak Ada Foto di Perangkat' : 'Belum Ada Foto di Server',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isDevice
                  ? 'Foto dan video dari kamera iPhone Anda akan muncul rapi di sini.'
                  : 'Cadangkan foto dari iPhone Anda untuk menyimpannya di host server MacBook / Windows.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),
            if (!isDevice && widget.onNavigateToSync != null)
              FilledButton.icon(
                onPressed: widget.onNavigateToSync,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('Mulai Cadangkan Foto'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme, String err) {
    final isServer = widget.controller.viewMode == GalleryViewMode.server;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isServer ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
              size: 56,
              color: Colors.orange.shade700,
            ),
            const SizedBox(height: 16),
            Text(
              isServer ? 'Server Belum Terhubung' : 'Gagal Memuat Galeri',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              err,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: widget.controller.fetchGallery,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Coba Lagi'),
                ),
                if (isServer && widget.onNavigateToSync != null)
                  OutlinedButton.icon(
                    onPressed: widget.onNavigateToSync,
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: const Text('Cek Jaringan / Server'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
