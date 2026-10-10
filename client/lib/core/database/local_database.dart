import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'asset_sync_entity.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('local_sync_index.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Initialize FFI for desktop platforms
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String dbPath;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final appDocDir = await getApplicationSupportDirectory();
      dbPath = join(appDocDir.path, filePath);
    } else {
      final defaultDatabasesPath = await getDatabasesPath();
      dbPath = join(defaultDatabasesPath, filePath);
    }

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE synced_assets (
        asset_id TEXT PRIMARY KEY,
        hash TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT,
        file_size INTEGER NOT NULL,
        mime_type TEXT NOT NULL,
        status TEXT NOT NULL,
        server_id INTEGER,
        synced_at TEXT,
        last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_synced_assets_hash ON synced_assets(hash)');
    await db.execute('CREATE INDEX idx_synced_assets_status ON synced_assets(status)');
  }

  Future<int> insertOrUpdate(AssetSyncEntity entity) async {
    final db = await database;
    return await db.insert(
      'synced_assets',
      entity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AssetSyncEntity?> getByAssetId(String assetId) async {
    final db = await database;
    final results = await db.query(
      'synced_assets',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return AssetSyncEntity.fromMap(results.first);
    }
    return null;
  }

  Future<AssetSyncEntity?> getByHash(String hash) async {
    final db = await database;
    final results = await db.query(
      'synced_assets',
      where: 'hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return AssetSyncEntity.fromMap(results.first);
    }
    return null;
  }

  Future<bool> isAssetSynced(String assetId) async {
    final db = await database;
    final results = await db.query(
      'synced_assets',
      columns: ['status'],
      where: 'asset_id = ? AND status = ?',
      whereArgs: [assetId, SyncStatus.synced.name],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  Future<void> markSynced(String hash, int serverId) async {
    final db = await database;
    await db.update(
      'synced_assets',
      {
        'status': SyncStatus.synced.name,
        'server_id': serverId,
        'synced_at': DateTime.now().toIso8601String(),
        'last_error': null,
      },
      where: 'hash = ?',
      whereArgs: [hash],
    );
  }

  Future<void> markSyncedByAssetId(String assetId, {int serverId = 0, String? hash, int fileSize = 0}) async {
    final db = await database;
    final count = await db.update(
      'synced_assets',
      {
        'status': SyncStatus.synced.name,
        'server_id': serverId,
        'synced_at': DateTime.now().toIso8601String(),
        'last_error': null,
        if (fileSize > 0) 'file_size': fileSize,
      },
      where: 'asset_id = ?',
      whereArgs: [assetId],
    );
    if (count == 0) {
      await markAssetSynced(assetId, hash ?? '', serverId: serverId, fileSize: fileSize);
    }
  }

  Future<Map<int, String>> getServerIdToAssetIdMap() async {
    final db = await database;
    final results = await db.query(
      'synced_assets',
      columns: ['server_id', 'asset_id'],
      where: 'server_id IS NOT NULL AND server_id > 0',
    );
    final map = <int, String>{};
    for (final row in results) {
      final sId = row['server_id'] as int?;
      final aId = row['asset_id'] as String?;
      if (sId != null && aId != null) {
        map[sId] = aId;
      }
    }
    return map;
  }

  Future<void> markAssetSynced(String assetId, String hash, {int serverId = 0, int fileSize = 0}) async {
    final db = await database;
    await db.rawInsert('''
      INSERT INTO synced_assets (asset_id, hash, file_name, file_size, mime_type, status, server_id, synced_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(asset_id) DO UPDATE SET
        status = excluded.status,
        server_id = excluded.server_id,
        synced_at = excluded.synced_at,
        file_size = CASE WHEN excluded.file_size > 0 THEN excluded.file_size ELSE synced_assets.file_size END
    ''', [
      assetId,
      hash,
      assetId,
      fileSize,
      'unknown',
      SyncStatus.synced.name,
      serverId,
      DateTime.now().toIso8601String(),
      DateTime.now().toIso8601String(),
    ]);
  }

  Future<int> getSyncedTotalBytes() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(file_size) as total_bytes FROM synced_assets WHERE status = ?',
      [SyncStatus.synced.name],
    );
    if (result.isNotEmpty && result.first['total_bytes'] != null) {
      return (result.first['total_bytes'] as num).toInt();
    }
    return 0;
  }

  Future<Set<String>> getAllSyncedAssetIds() async {
    final db = await database;
    final results = await db.query(
      'synced_assets',
      columns: ['asset_id'],
      where: 'status = ?',
      whereArgs: [SyncStatus.synced.name],
    );
    return results.map((row) => row['asset_id'] as String).toSet();
  }

  Future<Set<String>> getAllSyncedHashes() async {
    final db = await database;
    final results = await db.query(
      'synced_assets',
      columns: ['hash'],
      where: 'status = ?',
      whereArgs: [SyncStatus.synced.name],
    );
    return results.map((row) => row['hash'] as String).toSet();
  }

  Future<void> markFailed(String assetId, String error) async {
    final db = await database;
    await db.update(
      'synced_assets',
      {
        'status': SyncStatus.failed.name,
        'last_error': error,
      },
      where: 'asset_id = ?',
      whereArgs: [assetId],
    );
  }

  Future<int> getSyncedCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM synced_assets WHERE status = ?',
      [SyncStatus.synced.name],
    ));
    return count ?? 0;
  }

  Future<int> getPendingCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM synced_assets WHERE status != ?',
      [SyncStatus.synced.name],
    ));
    return count ?? 0;
  }

  Future<List<AssetSyncEntity>> getRecentSynced({int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'synced_assets',
      where: 'status = ?',
      whereArgs: [SyncStatus.synced.name],
      orderBy: 'synced_at DESC',
      limit: limit,
    );
    return maps.map((m) => AssetSyncEntity.fromMap(m)).toList();
  }
}
