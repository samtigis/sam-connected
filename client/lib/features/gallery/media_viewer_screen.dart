import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../../core/models/gallery_media_item.dart';
import 'gallery_controller.dart';
import 'video_player_view.dart';

class MediaViewerScreen extends StatefulWidget {
  final List<GalleryMediaItem> items;
  final int initialIndex;
  final GalleryController controller;

  const MediaViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.controller,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  final TransformationController _transformController = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _isBackingUpCurrent = false;
  bool _isPullingCurrent = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transformController.value = Matrix4.identity()
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
    }
  }

  void _handleBackupCurrent(GalleryMediaItem item) async {
    if (_isBackingUpCurrent || item.isSynced) return;

    setState(() {
      _isBackingUpCurrent = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final success = await widget.controller.backupSingleAsset(item);

    if (mounted) {
      setState(() {
        _isBackingUpCurrent = false;
      });

      if (success) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF16A34A),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Berhasil mencadangkan "${item.title}" ke server!')),
              ],
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Gagal mencadangkan file ke server. Pastikan server aktif.'),
          ),
        );
      }
    }
  }

  void _handlePullCurrent(GalleryMediaItem item) async {
    if (_isPullingCurrent || item.localEntity != null) return;

    setState(() {
      _isPullingCurrent = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final success = await widget.controller.pullMediaToGallery(item);

    if (mounted) {
      setState(() {
        _isPullingCurrent = false;
        if (success) {
          final updated = widget.controller.allMedia.firstWhere(
            (m) => m.id == item.id,
            orElse: () => item,
          );
          widget.items[_currentIndex] = updated;
        }
      });

      if (success) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF16A34A),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Berhasil menarik "${item.title}" ke galeri foto!')),
              ],
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Gagal menarik file dari server ke galeri.'),
          ),
        );
      }
    }
  }

  void _showInfoSheet(BuildContext context, GalleryMediaItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Informasi Detail File',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                _buildInfoRow(ctx, 'Nama File', item.title, Icons.description_rounded),
                if (item.serverItem != null)
                  _buildInfoRow(
                    ctx,
                    'Perangkat Asal Pencadangan',
                    widget.controller.getDeviceFriendlyName(item.serverItem!.deviceId),
                    Icons.devices_rounded,
                  ),
                _buildInfoRow(
                  ctx,
                  'Galeri Perangkat Ini',
                  item.localEntity != null
                      ? 'Tersimpan di Galeri Perangkat ✅'
                      : 'Belum Ada di Galeri (dapat ditarik) ⚠️',
                  item.localEntity != null ? Icons.phone_iphone_rounded : Icons.phonelink_erase_rounded,
                  highlightColor: item.localEntity != null ? const Color(0xFF16A34A) : const Color(0xFF6B7280),
                ),
                _buildInfoRow(
                  ctx,
                  'Status Server',
                  item.isSynced ? 'Tersimpan Aman di Server ✅' : 'Belum Dicadangkan ⚠️',
                  item.isSynced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  highlightColor: item.isSynced ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
                ),
                _buildInfoRow(
                  ctx,
                  'Tipe Media',
                  item.isVideo ? 'Video (${item.formattedDuration})' : 'Foto / Gambar',
                  item.isVideo ? Icons.videocam_rounded : Icons.image_rounded,
                ),
                if (item.width > 0 && item.height > 0)
                  _buildInfoRow(
                    ctx,
                    'Resolusi',
                    '${item.width} × ${item.height} (${((item.width * item.height) / 1000000).toStringAsFixed(1)} MP)',
                    Icons.aspect_ratio_rounded,
                  ),
                _buildInfoRow(ctx, 'Tanggal Diambil', item.formattedDate, Icons.calendar_today_rounded),
                if (item.formattedFileSize.isNotEmpty)
                  _buildInfoRow(ctx, 'Ukuran File', item.formattedFileSize, Icons.storage_rounded),
                if (item.hash != null && item.hash!.isNotEmpty)
                  _buildInfoRow(
                    ctx,
                    'Checksum SHA-256',
                    item.hash!.length > 16 ? '${item.hash!.substring(0, 16)}...' : item.hash!,
                    Icons.fingerprint_rounded,
                  ),
                const SizedBox(height: 12),
                if (!item.isSynced && item.isLocal)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleBackupCurrent(item);
                      },
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('Cadangkan File Ini Sekarang'),
                    ),
                  ),
                if (item.localEntity == null && item.serverItem != null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handlePullCurrent(item);
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Tarik ke Galeri (Kualitas Asli 100%)'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? highlightColor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: highlightColor ?? theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: highlightColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('Tidak ada media', style: TextStyle(color: Colors.white))),
      );
    }

    final currentItem = widget.items[_currentIndex];
    final baseUrl = widget.controller.serverBaseUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.65),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentItem.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_currentIndex + 1} dari ${widget.items.length} • ${currentItem.formattedDate}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          // Backup status pill (only on local device media)
          if (currentItem.isLocal)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: currentItem.isSynced
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF16A34A)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Tercadangkan',
                            style: TextStyle(color: Color(0xFF22C55E), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )
                  : _isBackingUpCurrent
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent),
                          ),
                        )
                      : ActionChip(
                          avatar: const Icon(Icons.cloud_upload_rounded, size: 14, color: Colors.white),
                          label: const Text(
                            'Cadangkan',
                            style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          backgroundColor: const Color(0xFFEA580C),
                          onPressed: () => _handleBackupCurrent(currentItem),
                        ),
            )
          else if (currentItem.localEntity == null && currentItem.serverItem != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: _isPullingCurrent
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                      ),
                    )
                  : ActionChip(
                      avatar: const Icon(Icons.download_rounded, size: 14, color: Colors.white),
                      label: const Text(
                        'Tarik ke Galeri',
                        style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: const Color(0xFF2563EB),
                      onPressed: () => _handlePullCurrent(currentItem),
                    ),
            )
          else if (currentItem.serverItem != null && currentItem.serverItem!.deviceId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.devices_rounded, color: Colors.lightBlueAccent, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      widget.controller.getDeviceFriendlyName(currentItem.serverItem!.deviceId),
                      style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          // Info Details sheet
          IconButton(
            tooltip: 'Detail EXIF & Info',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => _showInfoSheet(context, currentItem),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.items.length,
        onPageChanged: (idx) {
          setState(() {
            _currentIndex = idx;
            _transformController.value = Matrix4.identity();
          });
        },
        itemBuilder: (ctx, index) {
          final item = widget.items[index];
          final isCurrent = index == _currentIndex;

          if (item.isVideo) {
            // Video Player
            return VideoPlayerView(
              key: ValueKey('video_${item.id}'),
              item: item,
              serverBaseUrl: baseUrl,
              isCurrentPage: isCurrent,
            );
          }

          // Photo Viewer with pinch and double-tap zoom
          return GestureDetector(
            onDoubleTapDown: (details) => _doubleTapDetails = details,
            onDoubleTap: _onDoubleTap,
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 1.0,
              maxScale: 5.0,
              child: Center(
                child: item.localEntity != null
                    ? AssetEntityImage(
                        item.localEntity!,
                        isOriginal: true,
                        fit: BoxFit.contain,
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              AssetEntityImage(
                                item.localEntity!,
                                isOriginal: false,
                                thumbnailSize: const ThumbnailSize(300, 300),
                                fit: BoxFit.contain,
                              ),
                              const CircularProgressIndicator(color: Colors.white54),
                            ],
                          );
                        },
                        errorBuilder: (ctx, err, stack) => const Center(
                          child: Icon(Icons.broken_image_rounded, size: 64, color: Colors.white38),
                        ),
                      )
                    : Image.network(
                        (item.isHeic && item.serverItem != null)
                            ? item.serverItem!.thumbnailUrl(baseUrl)
                            : (item.serverItem != null ? item.serverItem!.rawUrl(baseUrl) : ''),
                        fit: BoxFit.contain,
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          return const Center(child: CircularProgressIndicator(color: Colors.white54));
                        },
                        errorBuilder: (ctx, err, stack) {
                          if (item.serverItem != null) {
                            return Image.network(
                              item.serverItem!.thumbnailUrl(baseUrl),
                              fit: BoxFit.contain,
                              loadingBuilder: (ctx, child, progress) {
                                if (progress == null) return child;
                                return const Center(child: CircularProgressIndicator(color: Colors.white54));
                              },
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_rounded, size: 64, color: Colors.white38),
                              ),
                            );
                          }
                          return const Center(
                            child: Icon(Icons.broken_image_rounded, size: 64, color: Colors.white38),
                          );
                        },
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
