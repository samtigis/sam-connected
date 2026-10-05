import 'package:flutter/material.dart';
import '../../core/models/media_item.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Cari nama file foto/video...',
                  border: InputBorder.none,
                ),
                onChanged: ctrl.setSearchQuery,
              )
            : Row(
                children: [
                  const Icon(Icons.photo_library_rounded, size: 22),
                  const SizedBox(width: 8),
                  const Text('Galeri Server'),
                  if (ctrl.totalServerCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${ctrl.totalServerCount}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
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
          preferredSize: const Size.fromHeight(48),
          child: _buildFilterBar(theme),
        ),
      ),
      body: ctrl.isLoading && ctrl.timelineGroups.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ctrl.errorMessage != null && ctrl.timelineGroups.isEmpty
              ? _buildErrorView(theme, ctrl.errorMessage!)
              : ctrl.timelineGroups.isEmpty
                  ? _buildEmptyView(theme)
                  : RefreshIndicator(
                      onRefresh: ctrl.fetchGallery,
                      child: CustomScrollView(
                        slivers: [
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
                                    return _buildMediaTile(ctx, item, ctrl.allMedia);
                                  },
                                  childCount: group.items.length,
                                ),
                              ),
                            ),
                            const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 32)),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip('Semua', GalleryFilter.all, Icons.grid_view_rounded),
          const SizedBox(width: 8),
          _buildFilterChip('Foto', GalleryFilter.photos, Icons.image_rounded),
          const SizedBox(width: 8),
          _buildFilterChip('Video', GalleryFilter.videos, Icons.videocam_rounded),
          const SizedBox(width: 8),
          _buildFilterChip('Favorit', GalleryFilter.favorites, Icons.favorite_rounded),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, GalleryFilter filter, IconData icon) {
    final isSelected = widget.controller.currentFilter == filter;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
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

  Widget _buildMediaTile(BuildContext context, MediaItem item, List<MediaItem> allItems) {
    final baseUrl = widget.controller.serverBaseUrl;
    final thumbUrl = item.thumbnailUrl(baseUrl);

    return InkWell(
      onTap: () {
        final initialIdx = allItems.indexWhere((m) => m.id == item.id);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MediaViewerScreen(
              items: allItems,
              initialIndex: initialIdx != -1 ? initialIdx : 0,
              controller: widget.controller,
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            thumbUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey.shade200,
              child: const Icon(Icons.image_not_supported_rounded, color: Colors.grey),
            ),
          ),
          if (item.isVideo)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 2),
                    Text(
                      'Video',
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          if (item.isFavorite)
            const Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.favorite_rounded,
                color: Colors.redAccent,
                size: 14,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyView(ThemeData theme) {
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
                Icons.photo_library_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Belum Ada Foto di Server',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Foto dan video yang dicadangkan dari iPhone Anda akan muncul rapi di sini layaknya Google Photos.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),
            if (widget.onNavigateToSync != null)
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Tidak Dapat Terhubung ke Server',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              err,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: widget.controller.fetchGallery,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
