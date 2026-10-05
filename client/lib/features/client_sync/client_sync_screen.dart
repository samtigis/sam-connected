import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/database/asset_sync_entity.dart';
import '../../core/database/local_database.dart';
import '../../core/network/api_client.dart';
import '../../core/network/discovery_service.dart';
import '../../core/role/role_controller.dart';
import '../onboarding/role_selection_screen.dart';
import 'gallery_scanner_service.dart';
import 'sync_coordinator.dart';

class ClientSyncScreen extends StatefulWidget {
  const ClientSyncScreen({super.key});

  @override
  State<ClientSyncScreen> createState() => _ClientSyncScreenState();
}

class _ClientSyncScreenState extends State<ClientSyncScreen> {
  late final ApiClient _apiClient;
  late final GalleryScannerService _scannerService;
  late final SyncCoordinator _syncCoordinator;
  late final DiscoveryService _discoveryService;
  final RoleController _roleController = RoleController();
  final LocalDatabase _localDb = LocalDatabase.instance;

  String _currentServerUrl = 'http://127.0.0.1:8080/api/v1';
  int _syncedCount = 0;
  int _pendingCount = 0;
  List<AssetSyncEntity> _recentSyncedAssets = [];

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(baseUrl: _currentServerUrl);
    _scannerService = GalleryScannerService();
    _syncCoordinator = SyncCoordinator(
      apiClient: _apiClient,
      scannerService: _scannerService,
    );
    _discoveryService = DiscoveryService();

    _syncCoordinator.addListener(_onSyncUpdate);
    _discoveryService.addListener(_onDiscoveryUpdate);

    // Start looking for local host server via mDNS
    _discoveryService.startDiscovery();
    _refreshStats();
  }

  void _onSyncUpdate() {
    if (mounted) {
      setState(() {});
      if (!_syncCoordinator.state.isSyncing) {
        _refreshStats();
      }
    }
  }

  void _onDiscoveryUpdate() {
    if (_discoveryService.servers.isNotEmpty &&
        _currentServerUrl == 'http://127.0.0.1:8080/api/v1') {
      final firstFound = _discoveryService.servers.first;
      _setServer(firstFound.baseUrl);
    }
    if (mounted) setState(() {});
  }

  Future<void> _refreshStats() async {
    final synced = await _localDb.getSyncedCount();
    final pending = await _localDb.getPendingCount();
    final recent = await _localDb.getRecentSynced(limit: 20);

    if (mounted) {
      setState(() {
        _syncedCount = synced;
        _pendingCount = pending;
        _recentSyncedAssets = recent;
      });
    }
  }

  void _setServer(String url) {
    setState(() {
      _currentServerUrl = url;
      _apiClient.updateBaseUrl(url);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Terhubung ke host: $url')),
    );
  }

  void _showManualServerDialog() {
    final controller = TextEditingController(text: _currentServerUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Masukkan Alamat Host Server'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.100:8080/api/v1',
            labelText: 'Server Base URL',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                _setServer(text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _switchRole() async {
    _discoveryService.stopDiscovery();
    await _roleController.resetRole();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RoleSelectionScreen(roleController: _roleController),
      ),
    );
  }

  @override
  void dispose() {
    _syncCoordinator.removeListener(_onSyncUpdate);
    _discoveryService.removeListener(_onDiscoveryUpdate);
    _syncCoordinator.dispose();
    _discoveryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final syncState = _syncCoordinator.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Uploader Galeri'),
        actions: [
          IconButton(
            tooltip: 'Ubah Peran (Ganti ke Mode Server)',
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: _switchRole,
          ),
          IconButton(
            tooltip: 'Server Manual',
            icon: const Icon(Icons.settings_ethernet_rounded),
            onPressed: _showManualServerDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Server Discovery Status Bar
              _buildServerStatusBar(theme),
              const SizedBox(height: 16),

              // Main Backup Card
              _buildHeroSyncCard(theme, syncState),
              const SizedBox(height: 20),

              // Stats Row
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      theme: theme,
                      label: 'Tersinkron',
                      value: '$_syncedCount',
                      icon: Icons.check_circle_rounded,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricTile(
                      theme: theme,
                      label: 'Antrean Baru',
                      value: '$_pendingCount',
                      icon: Icons.schedule_rounded,
                      color: Colors.amber.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricTile(
                      theme: theme,
                      label: 'Dilewati (Duplikat)',
                      value: '${syncState.skippedCount}',
                      icon: Icons.filter_none_rounded,
                      color: Colors.blueGrey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Timeline of Recently Synced Assets
              Text(
                'Aset Terbaru Tercadangkan',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildRecentSyncedList(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerStatusBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_tethering_rounded, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tujuan Host Server:',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                ),
                Text(
                  _currentServerUrl,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_discoveryService.servers.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.arrow_drop_down_circle_outlined),
              tooltip: 'Ditemukan ${_discoveryService.servers.length} server di Wi-Fi',
              onSelected: _setServer,
              itemBuilder: (ctx) => _discoveryService.servers
                  .map(
                    (s) => PopupMenuItem(
                      value: s.baseUrl,
                      child: Text('${s.name} (${s.host})'),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroSyncCard(ThemeData theme, SyncProgressState state) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: state.isSyncing
                      ? theme.colorScheme.primary.withOpacity(0.15)
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    state.isSyncing ? Icons.sync_rounded : Icons.cloud_upload_rounded,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isSyncing ? 'Sinkronisasi Berlangsung' : 'Auto-Backup Siap',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.statusMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (state.isSyncing) ...[
              const SizedBox(height: 20),
              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: state.totalToUpload > 0 ? (state.uploadedCount / state.totalToUpload) : null,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${state.uploadedCount} dari ${state.totalToUpload} file',
                    style: theme.textTheme.labelSmall,
                  ),
                  Text(
                    '${((state.totalToUpload > 0 ? (state.uploadedCount / state.totalToUpload) : 0) * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: state.isSyncing
                    ? () => _syncCoordinator.cancelSync()
                    : () => _syncCoordinator.startSync(),
                style: FilledButton.styleFrom(
                  backgroundColor: state.isSyncing ? Colors.redAccent : theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(state.isSyncing ? Icons.stop_rounded : Icons.play_arrow_rounded),
                label: Text(state.isSyncing ? 'Hentikan Sinkronisasi' : 'Mulai Cadangkan Sekarang'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required ThemeData theme,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSyncedList(ThemeData theme) {
    if (_recentSyncedAssets.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
        ),
        child: const Column(
          children: [
            Icon(Icons.photo_library_outlined, size: 40, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Belum ada foto yang tercadangkan.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recentSyncedAssets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _recentSyncedAssets[index];
        final isVideo = item.mimeType.startsWith('video');

        return ListTile(
          tileColor: theme.colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isVideo ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isVideo ? Icons.videocam_rounded : Icons.image_rounded,
              color: isVideo ? Colors.orange : Colors.blue,
            ),
          ),
          title: Text(
            item.fileName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${(item.fileSize / (1024 * 1024)).toStringAsFixed(1)} MB • ${item.syncedAt != null ? DateFormat('dd MMM, HH:mm').format(item.syncedAt!) : "Baru saja"}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
        );
      },
    );
  }
}
