import 'package:photo_manager/photo_manager.dart';
import 'media_item.dart';

enum MediaSourceType {
  localDevice,
  serverHost,
}

class GalleryMediaItem {
  final String id;
  final String title;
  final bool isVideo;
  final Duration videoDuration;
  final int width;
  final int height;
  final int fileSize;
  final DateTime createDateTime;
  final bool isSynced;
  final MediaSourceType sourceType;
  final AssetEntity? localEntity;
  final MediaItem? serverItem;
  final String? hash;

  GalleryMediaItem({
    required this.id,
    required this.title,
    required this.isVideo,
    this.videoDuration = Duration.zero,
    this.width = 0,
    this.height = 0,
    this.fileSize = 0,
    required this.createDateTime,
    required this.isSynced,
    required this.sourceType,
    this.localEntity,
    this.serverItem,
    this.hash,
  });

  bool get isLocal => sourceType == MediaSourceType.localDevice && localEntity != null;
  bool get isServer => sourceType == MediaSourceType.serverHost && serverItem != null;

  String get extension {
    if (serverItem != null && serverItem!.extension.isNotEmpty) {
      return serverItem!.extension;
    }
    final dot = title.lastIndexOf('.');
    return dot != -1 ? title.substring(dot).toLowerCase() : '';
  }

  bool get isHeic {
    final ext = extension.toLowerCase();
    return ext == '.heic' || ext == '.heif' || ext.contains('heic') || ext.contains('heif');
  }

  factory GalleryMediaItem.fromAssetEntity(
    AssetEntity entity, {
    required bool isSynced,
    String? hash,
  }) {
    return GalleryMediaItem(
      id: entity.id,
      title: entity.title ?? 'Media_${entity.id.substring(0, entity.id.length > 8 ? 8 : entity.id.length)}',
      isVideo: entity.type == AssetType.video,
      videoDuration: Duration(seconds: entity.duration),
      width: entity.width,
      height: entity.height,
      fileSize: 0,
      createDateTime: entity.createDateTime,
      isSynced: isSynced,
      sourceType: MediaSourceType.localDevice,
      localEntity: entity,
      hash: hash,
    );
  }

  factory GalleryMediaItem.fromServerItem(MediaItem item) {
    return GalleryMediaItem(
      id: item.id.toString(),
      title: item.fileName,
      isVideo: item.isVideo,
      videoDuration: Duration(seconds: item.duration.round()),
      width: item.width,
      height: item.height,
      fileSize: item.fileSize,
      createDateTime: item.displayDate,
      isSynced: true, // Always true since it exists on the server
      sourceType: MediaSourceType.serverHost,
      serverItem: item,
      hash: item.hash,
    );
  }

  GalleryMediaItem copyWith({
    bool? isSynced,
    String? hash,
    int? fileSize,
    AssetEntity? localEntity,
    Duration? videoDuration,
    int? width,
    int? height,
  }) {
    return GalleryMediaItem(
      id: id,
      title: title,
      isVideo: isVideo,
      videoDuration: videoDuration ?? this.videoDuration,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSize: fileSize ?? this.fileSize,
      createDateTime: createDateTime,
      isSynced: isSynced ?? this.isSynced,
      sourceType: sourceType,
      localEntity: localEntity ?? this.localEntity,
      serverItem: serverItem,
      hash: hash ?? this.hash,
    );
  }

  String get formattedDuration {
    final int hours = videoDuration.inHours;
    final int minutes = videoDuration.inMinutes.remainder(60);
    final int seconds = videoDuration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedFileSize {
    if (fileSize <= 0) return '';
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static const List<String> _indonesianMonths = [
    '',
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static String _formatIndonesianDate(DateTime d, {bool includeTime = false}) {
    final monthName = (d.month >= 1 && d.month <= 12) ? _indonesianMonths[d.month] : '${d.month}';
    final dateStr = '${d.day} $monthName ${d.year}';
    if (includeTime) {
      final hourStr = d.hour.toString().padLeft(2, '0');
      final minStr = d.minute.toString().padLeft(2, '0');
      return '$dateStr, $hourStr:$minStr';
    }
    return dateStr;
  }

  String get formattedDate {
    final now = DateTime.now();
    final d = createDateTime;
    final timeStr = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Hari ini, $timeStr';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
      return 'Kemarin, $timeStr';
    }
    return _formatIndonesianDate(d, includeTime: true);
  }

  String get dateGroupKey {
    final d = createDateTime;
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Hari Ini';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
      return 'Kemarin';
    }
    return _formatIndonesianDate(d, includeTime: false);
  }
}
