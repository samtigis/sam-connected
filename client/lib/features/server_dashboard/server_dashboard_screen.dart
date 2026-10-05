import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/role/role_controller.dart';
import '../onboarding/role_selection_screen.dart';
import 'server_sidecar_controller.dart';

class ServerDashboardScreen extends StatefulWidget {
  const ServerDashboardScreen({super.key});

  @override
  State<ServerDashboardScreen> createState() => _ServerDashboardScreenState();
}

class _ServerDashboardScreenState extends State<ServerDashboardScreen> {
  late final ServerSidecarController _serverController;
  final RoleController _roleController = RoleController();
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _serverController = ServerSidecarController();
    _serverController.addListener(_onControllerUpdate);

    // Auto-start server when opening dashboard on desktop
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _serverController.startServer();
    });
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _serverController.removeListener(_onControllerUpdate);
    _serverController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  String _formatBytes(dynamic bytes) {
    if (bytes == null) return '0 B';
    final int b = (bytes is int) ? bytes : (bytes as num).toInt();
    if (b <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double count = b.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _changeStorageFolder() async {
    final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pilih Lokasi Penyimpanan Baru (Misal HDD Eksternal 2TB)',
      initialDirectory: _serverController.storagePath,
    );

    if (selectedDirectory != null) {
      _serverController.setStoragePath(selectedDirectory);
      await _roleController.updateStoragePath(selectedDirectory);
      if (_serverController.isRunning) {
        // Restart daemon with new path
        await _serverController.stopServer();
        await _serverController.startServer();
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label disalin ke clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _switchRole() async {
    await _serverController.stopServer();
    await _roleController.resetRole();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RoleSelectionScreen(roleController: _roleController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disk = _serverController.diskMetrics;
    final double usedPercent = (disk?['used_percent'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            const Icon(Icons.dns_rounded, size: 22),
            const Text('Host Storage Dashboard'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _serverController.isRunning
                    ? Colors.green.withOpacity(0.15)
                    : Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 4,
                    backgroundColor: _serverController.isRunning ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      _serverController.serverStatus,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _serverController.isRunning ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ubah Peran (Ganti ke Mode Client)',
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: _switchRole,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Controls & Metrics
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Network Host Address Card
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Alamat Akses Jaringan Lokal',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Icon(Icons.wifi_rounded, color: theme.colorScheme.primary),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    'http://${_serverController.localIp}:${_serverController.port}/api/v1',
                                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  onPressed: () => _copyToClipboard(
                                    'http://${_serverController.localIp}:${_serverController.port}/api/v1',
                                    'Alamat API',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.broadcast_on_personal_rounded, size: 16, color: Colors.teal),
                              const SizedBox(width: 6),
                              Text(
                                'mDNS Broadcast Aktif: _photobackup._tcp (Port ${_serverController.port})',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.teal),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Storage Space & Folder Card
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Kapasitas Penyimpanan (HDD)',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Icon(Icons.folder_shared_rounded, color: theme.colorScheme.secondary),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: usedPercent / 100.0,
                              minHeight: 12,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              color: usedPercent > 90 ? Colors.red : theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Terpakai: ${_formatBytes(disk?["used_bytes"])} (${usedPercent.toStringAsFixed(1)}%)',
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(
                                'Sisa Bebas: ${_formatBytes(disk?["free_bytes"])}',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          Text(
                            'Lokasi Direktori Penyimpanan:',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _serverController.storagePath.isEmpty
                                      ? 'Belum dipilih'
                                      : _serverController.storagePath,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _changeStorageFolder,
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: const Text('Ganti Folder'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Server Engine Control Card
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kontrol Daemon Engine',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _serverController.isRunning
                                      ? 'Daemon Go sedang berjalan menerima koneksi uploader'
                                      : 'Daemon sedang berhenti',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _serverController.isStarting
                                ? null
                                : (_serverController.isRunning
                                    ? () => _serverController.stopServer()
                                    : () => _serverController.startServer()),
                            style: FilledButton.styleFrom(
                              backgroundColor: _serverController.isRunning ? Colors.redAccent : Colors.teal,
                            ),
                            icon: Icon(
                              _serverController.isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                            ),
                            label: Text(_serverController.isRunning ? 'Hentikan Server' : 'Nyalakan Server'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right Column: Live Ingestion Log
          Expanded(
            flex: 4,
            child: Container(
              margin: const EdgeInsets.only(top: 20, right: 20, bottom: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.terminal_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Live Server Logs',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Text(
                          '${_serverController.logs.length} baris',
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _serverController.logs.isEmpty
                        ? const Center(
                            child: Text(
                              'Menunggu aktivitas server...',
                              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                            ),
                          )
                        : ListView.builder(
                            controller: _logScrollController,
                            padding: const EdgeInsets.all(12),
                            itemCount: _serverController.logs.length,
                            itemBuilder: (context, index) {
                              final log = _serverController.logs[index];
                              final isError = log.contains('ERR') || log.contains('error');
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  log,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: isError ? Colors.redAccent : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
