import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/role/role_controller.dart';
import '../client_sync/client_sync_screen.dart';
import '../server_dashboard/server_dashboard_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  final RoleController roleController;

  const RoleSelectionScreen({
    super.key,
    required this.roleController,
  });

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String? _selectedStoragePath;
  bool _isSelectingFolder = false;

  Future<void> _pickStorageFolder() async {
    setState(() => _isSelectingFolder = true);
    try {
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Pilih Folder Penyimpanan Backup (Contoh: HDD 2TB)',
      );
      if (selectedDirectory != null) {
        setState(() {
          _selectedStoragePath = selectedDirectory;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memilih folder: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSelectingFolder = false);
      }
    }
  }

  void _confirmRole(AppRole role) async {
    try {
      await widget.roleController.setRole(
        role,
        customStoragePath: _selectedStoragePath,
      );

      if (!mounted) return;

      if (role == AppRole.serverHost) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ServerDashboardScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ClientSyncScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = RoleController.isDesktopPlatform;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Tentang Sam Connected',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'Sam Connected',
                applicationVersion: 'v1.0.0',
                applicationIcon: const Icon(Icons.cloud_sync_rounded, size: 48, color: Colors.blue),
                applicationLegalese: 'Hak Cipta © 2026 Sam Connected.\nDikembangkan oleh Sam Tigis.',
                children: [
                  const SizedBox(height: 12),
                  const Text(
                    'Solusi pencadangan foto & video otomatis lokal berkecepatan tinggi tanpa cloud publik. Mengubah PC/laptop Anda menjadi private storage mandiri di jaringan Wi-Fi rumah.',
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.cloud_sync_rounded,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Sam Connected',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pilih peran perangkat ini dalam jaringan backup lokal Anda',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Role Cards
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 650;
                        final cards = [
                          // Mode Server Card
                          _buildRoleCard(
                            context: context,
                            title: 'Mode Server / Host Storage',
                            subtitle: isDesktop
                                ? 'Jalankan daemon server Go di latar belakang. Menerima backup foto/video dari perangkat lain.'
                                : 'Hanya tersedia di Desktop (Windows & macOS).',
                            icon: Icons.dns_rounded,
                            accentColor: Colors.teal,
                            isEnabled: isDesktop,
                            badge: 'Desktop Only',
                            extraWidget: isDesktop
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: OutlinedButton.icon(
                                      onPressed: _isSelectingFolder ? null : _pickStorageFolder,
                                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                                      label: Text(
                                        _selectedStoragePath != null
                                            ? 'Penyimpanan: ...${_selectedStoragePath!.substring(_selectedStoragePath!.length > 25 ? _selectedStoragePath!.length - 25 : 0)}'
                                            : 'Pilih Lokasi HDD 2TB',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                : null,
                            onSelect: () => _confirmRole(AppRole.serverHost),
                          ),

                          // Mode Client Card
                          _buildRoleCard(
                            context: context,
                            title: 'Mode Client / Uploader',
                            subtitle:
                                'Otomatis cadangkan foto & video dari galeri lokal ke Server Host di jaringan Wi-Fi Anda.',
                            icon: Icons.phone_android_rounded,
                            accentColor: Colors.indigo,
                            isEnabled: true,
                            badge: 'Semua Perangkat',
                            onSelect: () => _confirmRole(AppRole.clientUploader),
                          ),
                        ];

                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: cards.map((c) => Expanded(child: c)).toList(),
                          );
                        } else {
                          return Column(
                            children: cards
                                .map((c) => Padding(
                                      padding: const EdgeInsets.only(bottom: 20),
                                      child: c,
                                    ))
                                .toList(),
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 32),
                    Text(
                      'Pilihan ini dapat diubah sewaktu-waktu di menu Pengaturan aplikasi.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isEnabled,
    required String badge,
    required VoidCallback onSelect,
    Widget? extraWidget,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: isEnabled ? 2 : 0,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isEnabled
              ? theme.colorScheme.outlineVariant.withOpacity(0.6)
              : theme.colorScheme.outlineVariant.withOpacity(0.2),
        ),
      ),
      color: isEnabled ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isEnabled ? accentColor.withOpacity(0.12) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 32,
                    color: isEnabled ? accentColor : Colors.grey,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isEnabled ? theme.colorScheme.secondaryContainer : Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isEnabled ? theme.colorScheme.onSecondaryContainer : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isEnabled ? theme.colorScheme.onSurface : Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isEnabled ? theme.colorScheme.onSurfaceVariant : Colors.grey,
                height: 1.4,
              ),
            ),
            if (extraWidget != null) extraWidget,
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isEnabled ? onSelect : null,
                style: FilledButton.styleFrom(
                  backgroundColor: isEnabled ? accentColor : null,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Pilih ${title.split(' ').first}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
