import 'dart:io';
import 'package:dio/dio.dart';

class ApiClient {
  final Dio _dio;
  String _baseUrl;

  String get baseUrl => _baseUrl;

  ApiClient({String baseUrl = 'http://127.0.0.1:8080/api/v1'})
      : _baseUrl = baseUrl,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(minutes: 15),
          sendTimeout: const Duration(minutes: 30),
        ));

  void updateBaseUrl(String newUrl) {
    _baseUrl = newUrl;
    _dio.options.baseUrl = newUrl;
  }

  /// Detailed connection test to verify latency and storage status
  Future<ConnectionTestResult> testConnection({String? customUrl}) async {
    final targetUrl = customUrl ?? _baseUrl;
    final stopwatch = Stopwatch()..start();
    try {
      final testDio = Dio(BaseOptions(
        baseUrl: targetUrl,
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      ));
      final response = await testDio.get('/ping');
      stopwatch.stop();

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final disk = data['disk'] as Map<String, dynamic>?;
        final freeBytes = (disk?['free_bytes'] as num?)?.toInt() ?? 0;
        final totalBytes = (disk?['total_bytes'] as num?)?.toInt() ?? 0;
        final serviceName = data['service']?.toString() ?? 'Sam Connected Server';

        return ConnectionTestResult(
          success: true,
          url: targetUrl,
          serviceName: serviceName,
          latencyMs: stopwatch.elapsedMilliseconds,
          freeBytes: freeBytes,
          totalBytes: totalBytes,
          message: 'Server aktif dan siap menerima pencadangan.',
        );
      }
      return ConnectionTestResult(
        success: false,
        url: targetUrl,
        latencyMs: stopwatch.elapsedMilliseconds,
        message: 'Respons server tidak sesuai (status ${response.statusCode}).',
      );
    } catch (e) {
      stopwatch.stop();
      return ConnectionTestResult(
        success: false,
        url: targetUrl,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: e.toString(),
        message: 'Tidak dapat terhubung ke server di $targetUrl.',
      );
    }
  }

  /// Check server health & dynamic storage capacity
  /// GET /api/v1/ping
  Future<Map<String, dynamic>> ping() async {
    try {
      final response = await _dio.get('/ping');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      throw DioException(
        requestOptions: response.requestOptions,
        error: 'Unexpected response status: ${response.statusCode}',
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Sends a batch of local SHA-256 hashes to check deduplication
  /// POST /api/v1/sync/preflight
  Future<List<String>> preflight({
    required String deviceId,
    required List<String> hashes,
  }) async {
    final response = await _dio.post(
      '/sync/preflight',
      data: {
        'device_id': deviceId,
        'hashes': hashes,
      },
    );

    if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
      final missing = response.data['missing_hashes'] as List<dynamic>?;
      if (missing != null) {
        return missing.map((e) => e.toString()).toList();
      }
    }
    return [];
  }

  /// Uploads media stream via multipart form
  /// POST /api/v1/sync/upload
  Future<Map<String, dynamic>> upload({
    required File file,
    required String deviceId,
    required String clientHash,
    DateTime? takenAt,
    int? width,
    int? height,
    double? duration,
    File? thumbnailFile,
    ProgressCallback? onSendProgress,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;

    final formData = FormData.fromMap({
      'device_id': deviceId,
      'client_hash': clientHash,
      if (takenAt != null) 'taken_at': takenAt.toIso8601String(),
      if (width != null && width > 0) 'width': width.toString(),
      if (height != null && height > 0) 'height': height.toString(),
      if (duration != null && duration > 0) 'duration': duration.toString(),
      'file': await MultipartFile.fromFile(
        file.path,
        filename: fileName,
      ),
      if (thumbnailFile != null && await thumbnailFile.exists())
        'thumbnail': await MultipartFile.fromFile(
          thumbnailFile.path,
          filename: '${fileName}_thumb.jpg',
        ),
    });

    final response = await _dio.post(
      '/sync/upload',
      data: formData,
      onSendProgress: onSendProgress,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data as Map<String, dynamic>;
    }

    throw DioException(
      requestOptions: response.requestOptions,
      error: 'Upload failed with status ${response.statusCode}: ${response.data}',
    );
  }

  /// Fetch remote media list with cursor pagination and optional filters
  /// GET /api/v1/media
  Future<Map<String, dynamic>> getMedia({
    int cursor = 0,
    int limit = 50,
    String? deviceId,
    String? type,
    bool? favorite,
    String? search,
    String order = 'desc',
  }) async {
    final response = await _dio.get(
      '/media',
      queryParameters: {
        'cursor': cursor,
        'limit': limit,
        'order': order,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        if (type != null && type.isNotEmpty) 'type': type,
        if (favorite != null) 'favorite': favorite,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// Fetch grouped media timeline (Google Photos style)
  /// GET /api/v1/media/timeline
  Future<Map<String, dynamic>> getMediaTimeline({
    String? deviceId,
    String? type,
    bool? favorite,
  }) async {
    final response = await _dio.get(
      '/media/timeline',
      queryParameters: {
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        if (type != null && type.isNotEmpty) 'type': type,
        if (favorite != null) 'favorite': favorite,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// Fetch all client devices that have backed up data to the server
  /// GET /api/v1/devices
  Future<List<Map<String, dynamic>>> getDevices() async {
    try {
      final response = await _dio.get('/devices');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final list = response.data['devices'] as List<dynamic>? ?? [];
        return list.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return [];
  }

  /// Get details of a single media item
  /// GET /api/v1/media/:id
  Future<Map<String, dynamic>> getMediaById(int id) async {
    final response = await _dio.get('/media/$id');
    return response.data as Map<String, dynamic>;
  }

  /// Toggle favorite status of a media item
  /// POST /api/v1/media/:id/favorite
  Future<bool> toggleFavorite(int id) async {
    final response = await _dio.post('/media/$id/favorite');
    if (response.data is Map<String, dynamic>) {
      return response.data['is_favorite'] == true;
    }
    return false;
  }

  /// Delete a media item from server disk and database
  /// DELETE /api/v1/media/:id
  Future<bool> deleteMedia(int id) async {
    final response = await _dio.delete('/media/$id');
    return response.statusCode == 200;
  }
}

class ConnectionTestResult {
  final bool success;
  final String url;
  final String serviceName;
  final int latencyMs;
  final int freeBytes;
  final int totalBytes;
  final String message;
  final String? error;

  ConnectionTestResult({
    required this.success,
    required this.url,
    this.serviceName = '',
    required this.latencyMs,
    this.freeBytes = 0,
    this.totalBytes = 0,
    required this.message,
    this.error,
  });

  String get formattedFreeDisk {
    if (freeBytes <= 0) return 'Tidak diketahui';
    final gb = freeBytes / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    final mb = freeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }
}

