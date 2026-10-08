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

  // Batch backup & pull state
  bool _isBatchBackingUp = false;
  bool _isBatchPulling = false;

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
      _isSelectionMode = false;
      _selectedIds.clear();
    });

    int successCount = 0;
    try {
      successCount = await widget.controller.backupSelectedAssets(
        itemsToBackup,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBatchBackingUp = false;
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

  Future<void> _startBatchPull(List<GalleryMediaItem> itemsToPull) async {
    if (itemsToPull.isEmpty || _isBatchPulling) return;

    setState(() {
      _isBatchPulling = true;
      _isSelectionMode = false;
      _selectedIds.clear();
    });

    int successCount = 0;
    try {
      successCount = await widget.controller.pullBatchToGallery(
        itemsToPull,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBatchPulling = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selesai! $successCount dari ${itemsToPull.length} media berhasil ditarik ke galeri perangkat tanpa kompresi.',
            ),
            backgroundColor: const Color(0xFF16A34A),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showMissingLocallyInfo(BuildContext context, GalleryMediaItem item) {
    final ctrl = widget.controller;
    final deviceId = item.serverItem?.deviceId ?? '';
    final deviceName = ctrl.getDeviceFriendlyName(deviceId);

    IconData devIcon = Icons.devices_rounded;
    final lower = (deviceId + deviceName).toLowerCase();
    if (lower.contains('ipad')) {
      devIcon = Icons.tablet_mac_rounded;
    } else if (lower.contains('iphone')) {
      devIcon = Icons.phone_iphone_rounded;
    } else if (lower.contains('android')) {
      devIcon = Icons.android_rounded;
    } else if (lower.contains('pc') || lower.contains('laptop') || lower.contains('windows')) {
      devIcon = Icons.laptop_windows_rounded;
    }

    bool isPulling = false;
    double pullProgress = 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final theme = Theme.of(context);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.priority_high_rounded,
                          size: 20,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Belum Ada di Galeri Perangkat',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'File aman di server, siap ditarik ke galeri ini',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Owner device card with rename option
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(devIcon, size: 28, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Perangkat Asal Pencadangan',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.outline,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                deviceName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Ubah Nama Perangkat',
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          onPressed: () {
                            _showRenameDeviceDialog(context, deviceId, deviceName);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Media Details
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow(context, 'Nama File', item.title),
                        const SizedBox(height: 6),
                        _buildDetailRow(
                          context,
                          'Tipe & Ukuran',
                          '${item.isVideo ? "Video" : "Foto"} • ${item.formattedFileSize.isNotEmpty ? item.formattedFileSize : "-"}',
                        ),
                        const SizedBox(height: 6),
                        _buildDetailRow(context, 'Tanggal', item.formattedDate),
                        if (item.width > 0 && item.height > 0) ...[
                          const SizedBox(height: 6),
                          _buildDetailRow(context, 'Dimensi', '${item.width} × ${item.height}'),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (isPulling) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Mengunduh Kualitas Asli 100%...',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${(pullProgress * 100).clamp(0, 100).toInt()}%',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: pullProgress > 0 ? pullProgress : null,
                              minHeight: 8,
                              backgroundColor: Colors.blue.withOpacity(0.15),
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (item.formattedFileSize.isNotEmpty)
                                Text(
                                  pullProgress > 0
                                      ? '${(pullProgress * item.fileSize / (1024 * 1024)).toStringAsFixed(1)} MB / ${item.formattedFileSize}'
                                      : item.formattedFileSize,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: theme.colorScheme.outline),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.download_rounded, color: Colors.white),
                        label: const Text(
                          'Tarik ke Galeri (Kualitas Asli 100%)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setSheetState(() {
                            isPulling = true;
                            pullProgress = 0.0;
                          });

                          final ok = await ctrl.pullMediaToGallery(
                            item,
                            onProgress: (p, speed) {
                              setSheetState(() {
                                pullProgress = p;
                              });
                            },
                          );

                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }

                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Berhasil disimpan ke Galeri Foto perangkat!'
                                      : 'Gagal menarik file dari server.',
                                ),
                                backgroundColor: ok ? const Color(0xFF16A34A) : Colors.red,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRenameDeviceDialog(BuildContext context, String deviceId, String currentName) {
    final textCtrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Beri Nama Perangkat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ID: $deviceId',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: textCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama Perangkat (contoh: iPad Pro / iPhone 15)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = textCtrl.text.trim();
              if (newName.isNotEmpty) {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(dlgCtx);
                await widget.controller.setDeviceFriendlyName(deviceId, newName);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Nama perangkat diperbarui menjadi "$newName"')),
                  );
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
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
                preferredSize: Size.fromHeight(ctrl.viewMode == GalleryViewMode.server ? 86 : 48),
                child: Column(
                  children: [
                    if (ctrl.viewMode == GalleryViewMode.server) ...[
                      _buildDeviceSelectorBar(theme, ctrl),
                      const SizedBox(height: 2),
                    ],
                    _buildFilterBar(theme, ctrl),
                  ],
                ),
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
                preferredSize: Size.fromHeight(ctrl.viewMode == GalleryViewMode.server ? 142 : 96),
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
                    if (ctrl.viewMode == GalleryViewMode.server) ...[
                      const SizedBox(height: 6),
                      _buildDeviceSelectorBar(theme, ctrl),
                    ],
                    const SizedBox(height: 4),
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

  Widget _buildDeviceSelectorBar(ThemeData theme, GalleryController ctrl) {
    final devices = ctrl.serverDevices;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(
              'Semua Perangkat (${ctrl.totalCount})',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            avatar: const Icon(Icons.devices_rounded, size: 14),
            selected: ctrl.selectedDeviceId == null,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => ctrl.setSelectedDevice(null),
          ),
          for (final dev in devices) ...[
            const SizedBox(width: 6),
            _buildDeviceChip(theme, ctrl, dev),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceChip(ThemeData theme, GalleryController ctrl, Map<String, dynamic> dev) {
    final devId = dev['device_id']?.toString() ?? '';
    final customName = dev['custom_name']?.toString() ?? '';
    final displayName = dev['display_name']?.toString() ?? '';
    final count = (dev['total_media'] as num?)?.toInt() ?? 0;
    final isSelected = ctrl.selectedDeviceId == devId;

    IconData icon = Icons.smartphone_rounded;
    String name = displayName.isNotEmpty
        ? displayName
        : (customName.isNotEmpty ? customName : devId);

    // If no custom name was given by server, format the devId nicely
    if (customName.isEmpty && displayName.isEmpty) {
      final lower = devId.toLowerCase();
      if (lower.contains('ipad')) {
        icon = Icons.tablet_mac_rounded;
        name = 'iPad';
      } else if (lower.contains('iphone')) {
        icon = Icons.phone_iphone_rounded;
        name = 'iPhone';
      } else if (lower.contains('android')) {
        icon = Icons.android_rounded;
        name = 'Android';
      } else if (lower.contains('windows') || lower.contains('pc')) {
        icon = Icons.laptop_windows_rounded;
        name = 'Windows PC';
      } else if (lower.contains('mac')) {
        icon = Icons.laptop_mac_rounded;
        name = 'MacBook';
      } else if (lower == 'localhost' || lower == 'default' || lower.isEmpty) {
        icon = Icons.devices_other_rounded;
        name = 'Perangkat Utama';
      }

      if (devId.contains('_')) {
        final parts = devId.split('_');
        if (parts.length >= 2 && parts.last.isNotEmpty) {
          final suffix = parts.last;
          if (lower.contains('ipad')) {
            name = 'iPad ($suffix)';
          } else if (lower.contains('iphone')) {
            name = 'iPhone ($suffix)';
          } else if (!lower.contains('localhost')) {
            name = devId.replaceAll('_', ' ');
          }
        }
      }
    } else {
      final lower = name.toLowerCase();
      if (lower.contains('ipad')) {
        icon = Icons.tablet_mac_rounded;
      } else if (lower.contains('iphone')) {
        icon = Icons.phone_iphone_rounded;
      } else if (lower.contains('android')) {
        icon = Icons.android_rounded;
      } else if (lower.contains('pc') || lower.contains('laptop') || lower.contains('windows')) {
        icon = Icons.laptop_windows_rounded;
      }
    }

    return ChoiceChip(
      label: Text('$name ($count)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      avatar: Icon(icon, size: 14),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => ctrl.setSelectedDevice(devId),
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
              'Belum Backup (${ctrl.unsyncedCount})',
              GalleryFilter.unsynced,
              Icons.warning_amber_rounded,
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              'Sudah Backup (${ctrl.syncedCount})',
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
            child: item.localEntity != null
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
                        errorBuilder: (_, __, ___) => item.isVideo
                            ? Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blueGrey.shade900,
                                      Colors.grey.shade900,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white.withOpacity(0.7),
                                    size: 38,
                                  ),
                                ),
                              )
                            : Container(
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
                      item.videoDuration > Duration.zero
                          ? item.formattedDuration
                          : 'Video',
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
          // ONLY display on Local Device gallery (Galeri Perangkat)
          // Green checkmark (centang) if synced, Amber/Orange exclamation (tanda seru) if unsynced
          if (ctrl.viewMode == GalleryViewMode.device)
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

          // Missing locally badge on Server Gallery:
          // "tanda seru abu abu kecil saja"
          // Muncul jika media ada di server namun belum ada di galeri perangkat (atau sudah dihapus dari galeri)
          if (ctrl.viewMode == GalleryViewMode.server && item.localEntity == null)
            Positioned(
              top: 5,
              right: 5,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showMissingLocallyInfo(context, item),
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF9CA3AF).withOpacity(0.85),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.priority_high_rounded,
                    size: 11,
                    color: Color(0xFFD1D5DB), // Light grey exclamation
                  ),
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
    final missingLocallySelected = selectedItems.where((i) => i.localEntity == null).toList();
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
                  )
                else
                  Text(
                    missingLocallySelected.isNotEmpty
                        ? '${missingLocallySelected.length} belum ada di galeri lokal'
                        : (_selectedIds.isNotEmpty ? 'Semua sudah ada di galeri lokal' : 'Ketuk media untuk memilih'),
                    style: TextStyle(
                      fontSize: 12,
                      color: missingLocallySelected.isNotEmpty
                          ? const Color(0xFF4B5563)
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
                    ? '(${widget.controller.activeTask.current}/${widget.controller.activeTask.total})'
                    : 'Cadangkan (${unsyncedSelected.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            )
          else if (!isDevice && missingLocallySelected.isNotEmpty)
            FilledButton.icon(
              onPressed: _isBatchPulling
                  ? null
                  : () => _startBatchPull(missingLocallySelected),
              icon: _isBatchPulling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 18, color: Colors.white),
              label: Text(
                _isBatchPulling
                    ? '(${widget.controller.activeTask.current}/${widget.controller.activeTask.total})'
                    : 'Tarik ke Galeri (${missingLocallySelected.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
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
