enum SyncStatus {
  pending,
  hashing,
  synced,
  failed,
}

class AssetSyncEntity {
  final String assetId; // ID from photo_manager
  final String hash; // SHA-256 hash
  final String fileName;
  final String? filePath;
  final int fileSize;
  final String mimeType;
  final SyncStatus status;
  final int? serverId;
  final DateTime? syncedAt;
  final String? lastError;
  final DateTime createdAt;

  AssetSyncEntity({
    required this.assetId,
    required this.hash,
    required this.fileName,
    this.filePath,
    required this.fileSize,
    required this.mimeType,
    this.status = SyncStatus.pending,
    this.serverId,
    this.syncedAt,
    this.lastError,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'asset_id': assetId,
      'hash': hash,
      'file_name': fileName,
      'file_path': filePath,
      'file_size': fileSize,
      'mime_type': mimeType,
      'status': status.name,
      'server_id': serverId,
      'synced_at': syncedAt?.toIso8601String(),
      'last_error': lastError,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AssetSyncEntity.fromMap(Map<String, dynamic> map) {
    return AssetSyncEntity(
      assetId: map['asset_id'] as String,
      hash: map['hash'] as String,
      fileName: map['file_name'] as String,
      filePath: map['file_path'] as String?,
      fileSize: map['file_size'] as int,
      mimeType: map['mime_type'] as String,
      status: SyncStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => SyncStatus.pending,
      ),
      serverId: map['server_id'] as int?,
      syncedAt: map['synced_at'] != null ? DateTime.tryParse(map['synced_at'] as String) : null,
      lastError: map['last_error'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String) ?? DateTime.now(),
    );
  }

  AssetSyncEntity copyWith({
    String? assetId,
    String? hash,
    String? fileName,
    String? filePath,
    int? fileSize,
    String? mimeType,
    SyncStatus? status,
    int? serverId,
    DateTime? syncedAt,
    String? lastError,
  }) {
    return AssetSyncEntity(
      assetId: assetId ?? this.assetId,
      hash: hash ?? this.hash,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      status: status ?? this.status,
      serverId: serverId ?? this.serverId,
      syncedAt: syncedAt ?? this.syncedAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt,
    );
  }
}
