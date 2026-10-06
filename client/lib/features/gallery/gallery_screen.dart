import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = widget.controller;

    // Collect all visible items across current timeline groups
    final List<GalleryMediaItem> visibleItems = [];
    for (final group in ctrl.timelineGroups) {
      visibleItems.addAll(group.items);
    }

    return Scaffold(
      appBar: AppBar(
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
                          if (ctrl.viewMode == GalleryViewMode.device)
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
                          const SliverToBoxAdapter(child: SizedBox(height: 36)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            group.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          Text(
            '${group.items.length} item',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTile(BuildContext context, GalleryMediaItem item, List<GalleryMediaItem> allItems) {
    final ctrl = widget.controller;

    return InkWell(
      onTap: () {
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
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail Image Surface
          if (item.isLocal && item.localEntity != null)
            AssetEntityImage(
              item.localEntity!,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize(250, 250),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
              ),
            )
          else if (item.isServer && item.serverItem != null)
            Image.network(
              item.serverItem!.thumbnailUrl(ctrl.serverBaseUrl),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
              ),
            )
          else
            Container(color: Colors.grey.shade300),

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
