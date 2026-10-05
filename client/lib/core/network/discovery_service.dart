import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

class DiscoveredHost {
  final String name;
  final String host;
  final int port;
  final String baseUrl;

  DiscoveredHost({
    required this.name,
    required this.host,
    required this.port,
  }) : baseUrl = 'http://$host:$port/api/v1';

  String get ip => host;

  @override
  String toString() => '$name ($baseUrl)';
}

class DiscoveryService extends ChangeNotifier {
  nsd.Discovery? _discovery;
  bool _isSearching = false;
  final List<DiscoveredHost> _servers = [];

  bool get isSearching => _isSearching;
  List<DiscoveredHost> get servers => List.unmodifiable(_servers);
  DiscoveredHost? get discoveredHost => _servers.isNotEmpty ? _servers.first : null;

  Future<void> startDiscovery() async {
    if (_isSearching) return;

    _isSearching = true;
    _servers.clear();
    notifyListeners();

    try {
      _discovery = await nsd.startDiscovery('_photobackup._tcp');
      _discovery!.addListener(() {
        final currentServices = _discovery!.services;
        _servers.clear();

        for (final service in currentServices) {
          final host = service.host;
          final port = service.port;
          final name = service.name ?? 'Sam Connected Server';

          if (host != null && port != null) {
            _servers.add(DiscoveredHost(
              name: name,
              host: host,
              port: port,
            ));
          }
        }
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[DiscoveryService] Error starting mDNS discovery: $e');
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> stopDiscovery() async {
    if (_discovery != null) {
      try {
        await nsd.stopDiscovery(_discovery!);
      } catch (e) {
        debugPrint('[DiscoveryService] Error stopping mDNS: $e');
      }
      _discovery = null;
    }
    _isSearching = false;
    notifyListeners();
  }

  void addManualHost(String host, int port) {
    final newHost = DiscoveredHost(
      name: 'Manual Server ($host)',
      host: host,
      port: port,
    );
    _servers.removeWhere((s) => s.baseUrl == newHost.baseUrl);
    _servers.insert(0, newHost);
    notifyListeners();
  }

  @override
  void dispose() {
    stopDiscovery();
    super.dispose();
  }
}
