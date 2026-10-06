import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/discovery_service.dart';

class ServerConnectionCard extends StatefulWidget {
  final DiscoveryService discoveryService;
  final ApiClient apiClient;
  final void Function(String newUrl)? onServerUrlChanged;

  const ServerConnectionCard({
    super.key,
    required this.discoveryService,
    required this.apiClient,
    this.onServerUrlChanged,
  });

  @override
  State<ServerConnectionCard> createState() => _ServerConnectionCardState();
}

class _ServerConnectionCardState extends State<ServerConnectionCard> {
  bool _isTesting = false;

  void _runConnectionTest() async {
    setState(() => _isTesting = true);

    final result = await widget.discoveryService.testConnection();

    if (!mounted) return;
    setState(() => _isTesting = false);

    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          result.success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                          color: result.success ? const Color(0xFF16A34A) : Colors.redAccent,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          result.success ? 'Koneksi Server Berhasil!' : 'Koneksi Server Gagal',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                _buildTestRow(
                  ctx,
                  'Alamat Server',
                  result.url.isNotEmpty ? result.url : widget.apiClient.baseUrl,
                  Icons.link_rounded,
                ),
                if (result.success) ...[
                  _buildTestRow(ctx, 'Identitas Service', result.serviceName, Icons.dns_rounded),
                  _buildTestRow(ctx, 'Latensi Jaringan', '${result.latencyMs} ms', Icons.speed_rounded),
                  if (result.freeBytes > 0)
                    _buildTestRow(
                      ctx,
                      'Kapasitas Bebas HDD',
                      result.formattedFreeDisk,
                      Icons.storage_rounded,
                    ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        result.error != null && result.error!.isNotEmpty
                            ? result.error!
                            : 'Server di ${result.url} tidak dapat dijangkau. Pastikan host server sudah berjalan dan berada di satu jaringan Wi-Fi.',
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (!result.success)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            widget.discoveryService.startDiscovery(forceRescan: true);
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Memulai pemindaian otomatis di Wi-Fi...')),
                            );
                          },
                          icon: const Icon(Icons.radar_rounded),
                          label: const Text('Pindai Jaringan'),
                        ),
                      ),
                    if (!result.success) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _runConnectionTest();
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Uji Lagi'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildTestRow(BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text('$label: ', style: TextStyle(color: theme.colorScheme.outline, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showManualServerDialog(BuildContext context) {
    final host = widget.discoveryService.activeHost;
    final ctrl = TextEditingController(text: host?.baseUrl ?? widget.apiClient.baseUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atur IP Server Manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan IP PC/Mac lokal tempat server Sam Connected dijalankan:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '192.168.1.15 atau http://192.168.1.15:8080/api/v1',
                labelText: 'IP / Alamat Server',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final val = ctrl.text.trim();
              Navigator.pop(ctx);
              if (val.isNotEmpty) {
                final res = await widget.discoveryService.setManualHost(val);
                if (widget.onServerUrlChanged != null && res.url.isNotEmpty) {
                  widget.onServerUrlChanged!(res.url);
                }
              }
            },
            child: const Text('Hubungkan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = widget.discoveryService;
    final host = ds.activeHost;
    final isOnline = ds.isServerOnline;
    final isSearching = ds.isSearching;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOnline
            ? const Color(0xFF16A34A).withOpacity(0.08)
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOnline
              ? const Color(0xFF16A34A).withOpacity(0.4)
              : theme.colorScheme.outlineVariant.withOpacity(0.6),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Status Badge Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline
                          ? const Color(0xFF16A34A)
                          : isSearching
                              ? Colors.amber
                              : Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOnline
                        ? 'SERVER LOKAL TERHUBUNG'
                        : isSearching
                            ? 'MEMINDAI JARINGAN WI-FI...'
                            : 'SERVER BELUM TERHUBUNG',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: isOnline
                          ? const Color(0xFF16A34A)
                          : isSearching
                              ? Colors.amber.shade800
                              : Colors.redAccent,
                    ),
                  ),
                ],
              ),
              if (host != null && host.discoveryMethod.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    host.discoveryMethod,
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Host Name & Network IP
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isOnline ? Icons.dns_rounded : Icons.wifi_find_rounded,
                size: 26,
                color: isOnline ? const Color(0xFF16A34A) : theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host?.name ?? 'Mencari Server Sam Connected...',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      host?.baseUrl ?? widget.apiClient.baseUrl,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isOnline && host != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (host.latencyMs > 0) ...[
                            Icon(Icons.speed_rounded, size: 12, color: theme.colorScheme.outline),
                            const SizedBox(width: 4),
                            Text(
                              '${host.latencyMs} ms',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (host.formattedFreeDisk.isNotEmpty) ...[
                            Icon(Icons.storage_rounded, size: 12, color: theme.colorScheme.outline),
                            const SizedBox(width: 4),
                            Text(
                              'Sisa HDD: ${host.formattedFreeDisk}',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Action Buttons: Test Koneksi, Pindai Ulang, Ubah IP
          Row(
            children: [
              // Test Koneksi Button
              Expanded(
                flex: 3,
                child: FilledButton.tonalIcon(
                  onPressed: _isTesting ? null : _runConnectionTest,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt_rounded, size: 16),
                  label: Text(_isTesting ? 'Menguji...' : 'Test Koneksi'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Pindai Ulang Button
              IconButton.outlined(
                tooltip: 'Pindai Ulang Server di Wi-Fi',
                visualDensity: VisualDensity.compact,
                icon: isSearching
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.radar_rounded, size: 18),
                onPressed: isSearching
                    ? null
                    : () {
                        ds.startDiscovery(forceRescan: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Memindai jaringan Wi-Fi untuk mendeteksi server...'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
              ),
              const SizedBox(width: 6),

              // Manual Edit Button
              IconButton.outlined(
                tooltip: 'Atur IP Manual',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_rounded, size: 18),
                onPressed: () => _showManualServerDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
