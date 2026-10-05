import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../client_sync/auto_sync_service.dart';

class SyncSettingsScreen extends StatefulWidget {
  final AutoSyncService autoSyncService;
  final String currentServerUrl;
  final Function(String) onUpdateServerUrl;

  const SyncSettingsScreen({
    super.key,
    required this.autoSyncService,
    required this.currentServerUrl,
    required this.onUpdateServerUrl,
  });

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.autoSyncService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    widget.autoSyncService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showEditServerDialog() {
    final ctrl = TextEditingController(text: widget.currentServerUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Alamat Server'),
        content: TextField(
          controller: ctrl,
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
              final text = ctrl.text.trim();
              if (text.isNotEmpty) {
                widget.onUpdateServerUrl(text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = widget.autoSyncService;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jadwal & Pengaturan'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // Status Overview Card
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.sync_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Status Pencadangan Otomatis',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    svc.lastSyncStatus,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    svc.lastSyncTime != null
                        ? 'Terakhir sinkron: ${DateFormat('d MMM yyyy, HH:mm').format(svc.lastSyncTime!)}'
                        : 'Belum pernah sinkronisasi',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: svc.isAutoSyncRunning
                        ? null
                        : () => svc.triggerAutoSync(reason: 'Manual'),
                    icon: svc.isAutoSyncRunning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(svc.isAutoSyncRunning ? 'Sedang Sinkronisasi...' : 'Sinkronkan Sekarang'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Section 1: Kapan Sinkronisasi Otomatis
          Text(
            'KAPAN SINKRONISASI OTOMATIS BERJALAN',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Aktifkan Pencadangan Otomatis'),
                  subtitle: const Text('Foto & video baru akan dicadangkan ke MacBook tanpa perlu repot'),
                  value: svc.autoSyncEnabled,
                  onChanged: svc.setAutoSyncEnabled,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Sinkron Saat Aplikasi Dibuka'),
                  subtitle: const Text('Pemeriksaan otomatis instan setiap kali Anda membuka Sam Connected'),
                  value: svc.syncOnAppOpen,
                  onChanged: svc.autoSyncEnabled ? svc.setSyncOnAppOpen : null,
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Interval Pencadangan Berkala'),
                  subtitle: Text(_intervalLabel(svc.syncIntervalMinutes)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  enabled: svc.autoSyncEnabled,
                  onTap: () => _showIntervalPicker(context, svc),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section 2: Aturan Jaringan & Baterai
          Text(
            'ATURAN KONEKSI & BATERAI',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Hanya Melalui Wi-Fi'),
                  subtitle: const Text('Mencegah penggunaan kuota seluler saat mencadangkan media besar'),
                  value: svc.wifiOnly,
                  onChanged: svc.setWifiOnly,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section 3: Pengaturan Server
          Text(
            'KONEKSI HOST SERVER',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: ListTile(
              title: const Text('Alamat Host Server'),
              subtitle: Text(
                widget.currentServerUrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              trailing: const Icon(Icons.edit_rounded, size: 20),
              onTap: _showEditServerDialog,
            ),
          ),
        ],
      ),
    );
  }

  String _intervalLabel(int minutes) {
    if (minutes <= 0) return 'Hanya saat aplikasi dibuka / manual';
    if (minutes == 15) return 'Setiap 15 Menit';
    if (minutes == 30) return 'Setiap 30 Menit';
    if (minutes == 60) return 'Setiap 1 Jam';
    if (minutes == 360) return 'Setiap 6 Jam';
    if (minutes == 1440) return 'Sekali Sehari (24 Jam)';
    return 'Setiap $minutes Menit';
  }

  void _showIntervalPicker(BuildContext context, AutoSyncService svc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Pilih Interval Pencadangan',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Divider(height: 1),
            _intervalOption(ctx, svc, 15, 'Setiap 15 Menit (Rekomendasi)'),
            _intervalOption(ctx, svc, 30, 'Setiap 30 Menit'),
            _intervalOption(ctx, svc, 60, 'Setiap 1 Jam'),
            _intervalOption(ctx, svc, 360, 'Setiap 6 Jam'),
            _intervalOption(ctx, svc, 1440, 'Sekali Sehari (24 Jam)'),
            _intervalOption(ctx, svc, 0, 'Nonaktif (Hanya Saat Aplikasi Dibuka)'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _intervalOption(BuildContext context, AutoSyncService svc, int minutes, String label) {
    final isSelected = svc.syncIntervalMinutes == minutes;
    return ListTile(
      title: Text(label),
      trailing: isSelected ? const Icon(Icons.check_rounded, color: Colors.blue) : null,
      onTap: () {
        svc.setSyncInterval(minutes);
        Navigator.pop(context);
      },
    );
  }
}
