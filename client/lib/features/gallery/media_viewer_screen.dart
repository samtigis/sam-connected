import 'package:flutter/material.dart';
import '../../core/models/media_item.dart';
import 'gallery_controller.dart';

class MediaViewerScreen extends StatefulWidget {
  final List<MediaItem> items;
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

  void _showInfoSheet(BuildContext context, MediaItem item) {
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
                _buildInfoRow(ctx, 'Nama File', item.fileName, Icons.image_rounded),
                _buildInfoRow(ctx, 'Ukuran', item.formattedFileSize, Icons.storage_rounded),
                if (item.width > 0 && item.height > 0)
                  _buildInfoRow(
                    ctx,
                    'Resolusi',
                    '${item.width} × ${item.height} (${((item.width * item.height) / 1000000).toStringAsFixed(1)} MP)',
                    Icons.aspect_ratio_rounded,
                  ),
                _buildInfoRow(ctx, 'Tanggal Diambil', item.formattedDate, Icons.calendar_today_rounded),
                _buildInfoRow(ctx, 'Tipe MIME', item.mimeType, Icons.category_rounded),
                _buildInfoRow(ctx, 'ID Perangkat Asal', item.deviceId, Icons.phone_iphone_rounded),
                _buildInfoRow(
                  ctx,
                  'Checksum SHA-256',
                  item.hash.length > 16 ? '${item.hash.substring(0, 16)}...' : item.hash,
                  Icons.fingerprint_rounded,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
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
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, MediaItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Media Ini?'),
        content: Text('File "${item.fileName}" akan dihapus permanen dari server MacBook Anda.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await widget.controller.deleteMedia(item);
      if (mounted) {
        if (success) {
          messenger.showSnackBar(
            const SnackBar(content: Text('File berhasil dihapus dari server')),
          );
          navigator.pop();
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('Gagal menghapus file dari server')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(body: Center(child: Text('Tidak ada media')));
    }

    final currentItem = widget.items[_currentIndex];
    final baseUrl = widget.controller.serverBaseUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.6),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentItem.fileName,
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
          // Favorite heart toggle
          IconButton(
            tooltip: currentItem.isFavorite ? 'Hapus dari Favorit' : 'Tambah ke Favorit',
            icon: Icon(
              currentItem.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: currentItem.isFavorite ? Colors.redAccent : Colors.white,
            ),
            onPressed: () {
              widget.controller.toggleFavorite(currentItem);
              setState(() {});
            },
          ),
          // Info Details sheet
          IconButton(
            tooltip: 'Detail EXIF & Info',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => _showInfoSheet(context, currentItem),
          ),
          // Delete
          IconButton(
            tooltip: 'Hapus dari Server',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _confirmDelete(context, currentItem),
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
          final imageUrl = item.rawUrl(baseUrl);
          final thumbUrl = item.thumbnailUrl(baseUrl);

          return GestureDetector(
            onDoubleTapDown: (details) => _doubleTapDetails = details,
            onDoubleTap: _onDoubleTap,
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 1.0,
              maxScale: 5.0,
              child: Center(
                child: item.isVideo
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.network(
                            thumbUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.videocam_rounded,
                              size: 72,
                              color: Colors.white38,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          // While loading raw original, show thumbnail as crisp low-res preview
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.network(thumbUrl, fit: BoxFit.contain),
                              const CircularProgressIndicator(color: Colors.white54),
                            ],
                          );
                        },
                        errorBuilder: (ctx, err, stack) => Image.network(
                          thumbUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_rounded, size: 64, color: Colors.white38),
                          ),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
