import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/discovery_service.dart';
import '../client_sync/auto_sync_service.dart';
import '../client_sync/client_sync_screen.dart';
import '../client_sync/gallery_scanner_service.dart';
import '../client_sync/sync_coordinator.dart';
import '../gallery/gallery_controller.dart';
import '../gallery/gallery_screen.dart';
import '../settings/sync_settings_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  final String initialServerUrl;

  const ClientHomeScreen({
    super.key,
    this.initialServerUrl = 'http://127.0.0.1:8080/api/v1',
  });

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  late final ApiClient _apiClient;
  late final GalleryScannerService _scannerService;
  late final SyncCoordinator _syncCoordinator;
  late final DiscoveryService _discoveryService;
  late final AutoSyncService _autoSyncService;
  late final GalleryController _galleryController;

  String _currentServerUrl = 'http://127.0.0.1:8080/api/v1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentServerUrl = widget.initialServerUrl;
    _apiClient = ApiClient(baseUrl: _currentServerUrl);
    _scannerService = GalleryScannerService();
    _syncCoordinator = SyncCoordinator(
      apiClient: _apiClient,
      scannerService: _scannerService,
    );
    _discoveryService = DiscoveryService();
    _autoSyncService = AutoSyncService(_syncCoordinator);
    _galleryController = GalleryController(_apiClient);

    // Listen to mDNS server discovery updates
    _discoveryService.addListener(_onDiscoveryUpdate);
    _discoveryService.startDiscovery();

    // Trigger auto-sync on app startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncService.onAppResume();
      _galleryController.fetchGallery();
    });
  }

  void _onDiscoveryUpdate() {
    if (_discoveryService.discoveredHost != null) {
      final host = _discoveryService.discoveredHost!;
      final newUrl = 'http://${host.ip}:${host.port}/api/v1';
      if (newUrl != _currentServerUrl) {
        _updateServerUrl(newUrl);
      }
    }
  }

  void _updateServerUrl(String newUrl) {
    setState(() {
      _currentServerUrl = newUrl;
      _apiClient.updateBaseUrl(newUrl);
    });
    _galleryController.fetchGallery();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _autoSyncService.onAppResume();
      _galleryController.fetchGallery();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _discoveryService.removeListener(_onDiscoveryUpdate);
    _discoveryService.dispose();
    _autoSyncService.dispose();
    _syncCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      GalleryScreen(
        controller: _galleryController,
        onNavigateToSync: () => setState(() => _currentIndex = 1),
      ),
      ClientSyncScreen(
        apiClient: _apiClient,
        syncCoordinator: _syncCoordinator,
        discoveryService: _discoveryService,
      ),
      SyncSettingsScreen(
        autoSyncService: _autoSyncService,
        currentServerUrl: _currentServerUrl,
        onUpdateServerUrl: _updateServerUrl,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() => _currentIndex = idx);
          if (idx == 0) {
            _galleryController.fetchGallery();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded),
            label: 'Galeri',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_sync_outlined),
            selectedIcon: Icon(Icons.cloud_sync_rounded),
            label: 'Cadangan',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_rounded),
            selectedIcon: Icon(Icons.schedule_rounded),
            label: 'Jadwal & Info',
          ),
        ],
      ),
    );
  }
}
