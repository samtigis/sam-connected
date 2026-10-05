import 'package:intl/intl.dart';

class MediaItem {
  final int id;
  final String deviceId;
  final String hash;
  final String fileName;
  final String filePath;
  final String? thumbnailPath;
  final bool hasThumbnail;
  final int fileSize;
  final String mimeType;
  final String extension;
  final int width;
  final int height;
  final double duration;
  final bool isFavorite;
  final DateTime? takenAt;
  final DateTime createdAt;

  MediaItem({
    required this.id,
    required this.deviceId,
    required this.hash,
    required this.fileName,
    required this.filePath,
    this.thumbnailPath,
    this.hasThumbnail = false,
    required this.fileSize,
    required this.mimeType,
    required this.extension,
    this.width = 0,
    this.height = 0,
    this.duration = 0.0,
    this.isFavorite = false,
    this.takenAt,
    required this.createdAt,
  });

  bool get isVideo =>
      mimeType.toLowerCase().startsWith('video/') ||
      ['.mp4', '.mov', '.m4v', '.avi', '.mkv'].contains(extension.toLowerCase());

  String thumbnailUrl(String baseUrl) => '$baseUrl/media/$id/thumb';
  String rawUrl(String baseUrl) => '$baseUrl/media/$id/raw';

  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  DateTime get displayDate => takenAt ?? createdAt;

  String get formattedDate {
    final now = DateTime.now();
    final d = displayDate;
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Hari ini, ${DateFormat('HH:mm').format(d)}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
      return 'Kemarin, ${DateFormat('HH:mm').format(d)}';
    }
    return DateFormat('d MMMM yyyy, HH:mm', 'id_ID').format(d);
  }

  String get dateGroupKey {
    final d = displayDate;
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Hari Ini';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
      return 'Kemarin';
    }
    return DateFormat('d MMMM yyyy', 'id_ID').format(d);
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return null;
      }
    }

    return MediaItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceId: json['device_id']?.toString() ?? '',
      hash: json['hash']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      filePath: json['file_path']?.toString() ?? '',
      thumbnailPath: json['thumbnail_path']?.toString(),
      hasThumbnail: json['has_thumbnail'] == true,
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      mimeType: json['mime_type']?.toString() ?? '',
      extension: json['extension']?.toString() ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      isFavorite: json['is_favorite'] == true,
      takenAt: parseDate(json['taken_at']),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  MediaItem copyWith({
    bool? isFavorite,
  }) {
    return MediaItem(
      id: id,
      deviceId: deviceId,
      hash: hash,
      fileName: fileName,
      filePath: filePath,
      thumbnailPath: thumbnailPath,
      hasThumbnail: hasThumbnail,
      fileSize: fileSize,
      mimeType: mimeType,
      extension: extension,
      width: width,
      height: height,
      duration: duration,
      isFavorite: isFavorite ?? this.isFavorite,
      takenAt: takenAt,
      createdAt: createdAt,
    );
  }
}
