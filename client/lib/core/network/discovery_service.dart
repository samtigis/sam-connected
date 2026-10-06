import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class DiscoveredHost {
  final String name;
  final String host;
  final int port;
  final String baseUrl;
  final String discoveryMethod;
  final int latencyMs;
  final int freeDiskBytes;
  final bool isOnline;
  final DateTime lastSeen;

  DiscoveredHost({
    required this.name,
    required this.host,
    required this.port,
    this.discoveryMethod = 'Otomatis',
    this.latencyMs = 0,
    this.freeDiskBytes = 0,
    this.isOnline = true,
    DateTime? lastSeen,
  })  : baseUrl = 'http://$host:$port/api/v1',
        lastSeen = lastSeen ?? DateTime.now();

  String get ip => host;

  String get formattedFreeDisk {
    if (freeDiskBytes <= 0) return '';
    final gb = freeDiskBytes / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    final mb = freeDiskBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  DiscoveredHost copyWith({
    String? name,
    String? host,
    int? port,
    String? discoveryMethod,
    int? latencyMs,
    int? freeDiskBytes,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return DiscoveredHost(
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      discoveryMethod: discoveryMethod ?? this.discoveryMethod,
      latencyMs: latencyMs ?? this.latencyMs,
      freeDiskBytes: freeDiskBytes ?? this.freeDiskBytes,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  String toString() => '$name ($ip:$port)';
}

class DiscoveryService extends ChangeNotifier {
  nsd.Discovery? _nsdDiscovery;
  RawDatagramSocket? _udpSocket;
  Timer? _udpPeriodicPingTimer;
  bool _isSearching = false;
  String _statusMessage = 'Mencari server...';

  final List<DiscoveredHost> _servers = [];
  DiscoveredHost? _activeHost;
  Timer? _heartbeatTimer;

  bool get isSearching => _isSearching;
  String get statusMessage => _statusMessage;
  List<DiscoveredHost> get servers => List.unmodifiable(_servers);
  DiscoveredHost? get activeHost => _activeHost;
  DiscoveredHost? get discoveredHost => _activeHost ?? (_servers.isNotEmpty ? _servers.first : null);
  bool get isServerOnline => _activeHost?.isOnline ?? false;

  DiscoveryService() {
    _startHeartbeat();
  }

  /// Starts full auto-discovery cycle:
  /// 1. Cached Last-Known Host
  /// 2. mDNS Zeroconf (_photobackup._tcp with IPv4 resolution)
  /// 3. Subnet LAN Probe Fallback
  Future<void> startDiscovery({bool forceRescan = false}) async {
    if (_isSearching && !forceRescan) return;

    _isSearching = true;
    _statusMessage = 'Memeriksa server tersimpan...';
    notifyListeners();

    // 1. Check cached last-known host first (Instant < 50ms)
    final cachedHost = await _loadCachedHost();
    if (cachedHost != null) {
      final isAlive = await _probeHost(cachedHost.host, cachedHost.port);
      if (isAlive != null) {
        _registerHost(isAlive);
        _statusMessage = 'Terhubung ke ${isAlive.name}';
        _isSearching = false;
        notifyListeners();
      }
    }

    // 2. Start UDP Discovery Beacon Listener & Broadcaster (Port 8088 - fastest on LAN)
    _statusMessage = 'Memindai sinyal server lokal (UDP & mDNS)...';
    notifyListeners();
    await _startUdpDiscovery();

    // 3. Start mDNS Zeroconf with IPv4 resolution
    await _startMdnsDiscovery();

    // 4. Fallback: Subnet LAN Scanner if no server active after short delay
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (_activeHost == null || !_activeHost!.isOnline || forceRescan) {
        await _scanLocalSubnet();
      }
      _isSearching = false;
      notifyListeners();
    });
  }

  /// Listens on UDP port 8088 for server presence beacons and broadcasts discovery requests
  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket?.close();
      _udpSocket = null;
      _udpPeriodicPingTimer?.cancel();

      // Try binding to UDP 8088 with address/port reuse
      try {
        _udpSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          8088,
          reuseAddress: true,
          reusePort: true,
        );
      } catch (_) {
        // Fallback to ephemeral port for broadcast sending/receiving
        _udpSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
        );
      }

      if (_udpSocket != null) {
        _udpSocket!.broadcastEnabled = true;
        _udpSocket!.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = _udpSocket?.receive();
            if (dg != null) {
              _handleUdpPacket(dg);
            }
          }
        });

        // Send discovery ping immediately and repeat after 600ms
        _sendUdpDiscoveryPing();
        _udpPeriodicPingTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) {
          if (_activeHost == null || !_activeHost!.isOnline) {
            _sendUdpDiscoveryPing();
          }
        });
      }
    } catch (e) {
      debugPrint('[DiscoveryService] UDP discovery setup warning: $e');
    }
  }

  void _sendUdpDiscoveryPing() {
    if (_udpSocket == null) return;
    try {
      final data = utf8.encode('SAM_CONNECTED_DISCOVER');
      // Broadcast to universal broadcast and common subnet masks
      _udpSocket?.send(data, InternetAddress('255.255.255.255'), 8088);
    } catch (_) {}
  }

  void _handleUdpPacket(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data).trim();
      if (!text.startsWith('{')) return;

      final map = jsonDecode(text) as Map<String, dynamic>;
      if (map['service'] == 'sam-connected-backup') {
        final String? status = map['status'];
        final String ip = (map['ip'] as String?)?.trim() ?? datagram.address.address;
        final int port = (map['port'] as num?)?.toInt() ?? 8080;
        final String name = (map['name'] as String?) ?? 'Sam Connected Server ($ip)';

        if (status == 'offline') {
          if (_activeHost != null && _activeHost!.host == ip) {
            _activeHost = _activeHost!.copyWith(isOnline: false);
            notifyListeners();
          }
          return;
        }

        // Server is online! Immediately probe and register
        _probeHost(ip, port, name: name, method: 'Sinyal Pancaran UDP (Port 8088)').then((probed) {
          if (probed != null) {
            _registerHost(probed);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _startMdnsDiscovery() async {
    try {
      if (_nsdDiscovery != null) {
        try {
          await nsd.stopDiscovery(_nsdDiscovery!);
        } catch (_) {}
        _nsdDiscovery = null;
      }

      _nsdDiscovery = await nsd.startDiscovery(
        '_photobackup._tcp',
        ipLookupType: nsd.IpLookupType.v4,
      );

      _nsdDiscovery!.addListener(() async {
        final services = _nsdDiscovery!.services;
        for (final service in services) {
          final port = service.port ?? 8080;
          final name = service.name ?? 'Sam Connected Server';

          // Resolve IPv4 address
          String? resolvedIp;
          if (service.addresses != null && service.addresses!.isNotEmpty) {
            for (final addr in service.addresses!) {
              if (addr.type == InternetAddressType.IPv4) {
                resolvedIp = addr.address;
                break;
              }
            }
          }

          if (resolvedIp == null && service.host != null && !service.host!.endsWith('.local')) {
            resolvedIp = service.host;
          }

          if (resolvedIp != null && resolvedIp.isNotEmpty) {
            final probed = await _probeHost(resolvedIp, port, name: name, method: 'Zeroconf mDNS');
            if (probed != null) {
              _registerHost(probed);
            }
          }
        }
      });
    } catch (e) {
      debugPrint('[DiscoveryService] mDNS discovery warning: $e');
    }
  }

  /// Probes local subnet by finding device's own Wi-Fi IP and pinging candidates on port 8080
  Future<void> _scanLocalSubnet() async {
    _statusMessage = 'Memindai jaringan Wi-Fi lokal (Port 8080)...';
    notifyListeners();

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final List<String> subnetPrefixes = [];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final prefix = '${parts[0]}.${parts[1]}.${parts[2]}.';
            if (!subnetPrefixes.contains(prefix)) {
              subnetPrefixes.add(prefix);
            }
          }
        }
      }

      if (subnetPrefixes.isEmpty) {
        subnetPrefixes.add('192.168.1.');
        subnetPrefixes.add('192.168.0.');
      }

      // Probing priority list: common router and LAN IP assignments
      final prioritySuffixes = [
        1, 2, 3, 4, 5, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
        50, 100, 101, 102, 103, 104, 105, 110, 111, 112, 113, 114, 115,
        120, 150, 200, 254
      ];

      // Add neighboring IPs close to device's own Wi-Fi IP for instant hit
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final mySuffix = int.tryParse(parts[3]);
            if (mySuffix != null) {
              for (int d = -5; d <= 5; d++) {
                final adj = mySuffix + d;
                if (adj > 1 && adj < 255 && !prioritySuffixes.contains(adj)) {
                  prioritySuffixes.insert(0, adj);
                }
              }
            }
          }
        }
      }

      for (final prefix in subnetPrefixes) {
        if (_activeHost != null && _activeHost!.isOnline) break;

        final candidateIps = prioritySuffixes.map((s) => '$prefix$s').toList();

        // Concurrently probe candidates in batches of 10
        const batchSize = 10;
        for (int i = 0; i < candidateIps.length; i += batchSize) {
          if (_activeHost != null && _activeHost!.isOnline) break;

          final end = (i + batchSize < candidateIps.length) ? i + batchSize : candidateIps.length;
          final batch = candidateIps.sublist(i, end);

          final results = await Future.wait(
            batch.map((ip) => _probeHost(ip, 8080, method: 'Pemindaian Subnet LAN')),
          );

          for (final found in results) {
            if (found != null) {
              _registerHost(found);
              _statusMessage = 'Server ditemukan di ${found.host}';
              notifyListeners();
              return;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DiscoveryService] Subnet scan error: $e');
    }
  }

  /// Probes an IP on port 8080 via /api/v1/ping
  Future<DiscoveredHost?> _probeHost(
    String ip,
    int port, {
    String? name,
    String method = 'Langsung',
  }) async {
    final dio = Dio(BaseOptions(
      baseUrl: 'http://$ip:$port/api/v1',
      connectTimeout: const Duration(milliseconds: 600),
      receiveTimeout: const Duration(milliseconds: 600),
    ));

    final stopwatch = Stopwatch()..start();
    try {
      final res = await dio.get('/ping');
      stopwatch.stop();

      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        if (data['service'] != null) {
          final disk = data['disk'] as Map<String, dynamic>?;
          final freeBytes = (disk?['free_bytes'] as num?)?.toInt() ?? 0;
          final serverName = name ?? 'Sam Connected Server ($ip)';

          return DiscoveredHost(
            name: serverName,
            host: ip,
            port: port,
            discoveryMethod: method,
            latencyMs: stopwatch.elapsedMilliseconds,
            freeDiskBytes: freeBytes,
            isOnline: true,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  void _registerHost(DiscoveredHost host) {
    _servers.removeWhere((s) => s.host == host.host && s.port == host.port);
    _servers.insert(0, host);

    _activeHost = host;
    _saveCachedHost(host);
    notifyListeners();
  }

  /// Manual override to connect to a specific server URL or IP
  Future<ConnectionTestResult> setManualHost(String input) async {
    String ip = input.trim();
    int port = 8080;

    // Parse URL if provided as http://ip:port/api/v1
    if (ip.startsWith('http://') || ip.startsWith('https://')) {
      final uri = Uri.tryParse(ip);
      if (uri != null) {
        ip = uri.host;
        port = uri.port > 0 ? uri.port : 8080;
      }
    } else if (ip.contains(':')) {
      final parts = ip.split(':');
      ip = parts[0];
      port = int.tryParse(parts[1]) ?? 8080;
    }

    final probed = await _probeHost(ip, port, method: 'Manual');
    if (probed != null) {
      _registerHost(probed);
      return ConnectionTestResult(
        success: true,
        url: probed.baseUrl,
        serviceName: probed.name,
        latencyMs: probed.latencyMs,
        freeBytes: probed.freeDiskBytes,
        message: 'Berhasil terhubung ke host manual!',
      );
    } else {
      final testUrl = 'http://$ip:$port/api/v1';
      final fallbackHost = DiscoveredHost(
        name: 'Server Manual ($ip)',
        host: ip,
        port: port,
        discoveryMethod: 'Manual',
        isOnline: false,
      );
      _registerHost(fallbackHost);
      return ConnectionTestResult(
        success: false,
        url: testUrl,
        latencyMs: 0,
        message: 'Server tidak merespons di $testUrl. Pastikan server aktif.',
      );
    }
  }

  /// Performs a live connection test for current active host or custom URL
  Future<ConnectionTestResult> testConnection({String? customUrl}) async {
    final targetUrl = customUrl ?? _activeHost?.baseUrl;
    if (targetUrl == null) {
      return ConnectionTestResult(
        success: false,
        url: '',
        latencyMs: 0,
        message: 'Belum ada alamat server yang dipilih.',
      );
    }

    final client = ApiClient(baseUrl: targetUrl);
    final result = await client.testConnection();

    if (_activeHost != null && result.url == _activeHost!.baseUrl) {
      _activeHost = _activeHost!.copyWith(
        isOnline: result.success,
        latencyMs: result.latencyMs,
        freeDiskBytes: result.freeBytes,
        lastSeen: DateTime.now(),
      );
      notifyListeners();
    }

    return result;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_activeHost != null) {
        final isAlive = await _probeHost(_activeHost!.host, _activeHost!.port);
        if (isAlive != null) {
          _activeHost = _activeHost!.copyWith(
            isOnline: true,
            latencyMs: isAlive.latencyMs,
            freeDiskBytes: isAlive.freeDiskBytes,
            lastSeen: DateTime.now(),
          );
        } else {
          _activeHost = _activeHost!.copyWith(isOnline: false);
          // If server went offline, trigger silent background re-discovery
          startDiscovery();
        }
        notifyListeners();
      } else {
        // No server yet -> try discovering
        startDiscovery();
      }
    });
  }

  Future<void> _saveCachedHost(DiscoveredHost host) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_server_ip', host.host);
      await prefs.setInt('cached_server_port', host.port);
      await prefs.setString('cached_server_name', host.name);
    } catch (_) {}
  }

  Future<DiscoveredHost?> _loadCachedHost() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ip = prefs.getString('cached_server_ip');
      final port = prefs.getInt('cached_server_port') ?? 8080;
      final name = prefs.getString('cached_server_name') ?? 'Sam Connected Server';

      if (ip != null && ip.isNotEmpty) {
        return DiscoveredHost(
          name: name,
          host: ip,
          port: port,
          discoveryMethod: 'Tersimpan',
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> stopDiscovery() async {
    if (_nsdDiscovery != null) {
      try {
        await nsd.stopDiscovery(_nsdDiscovery!);
      } catch (_) {}
      _nsdDiscovery = null;
    }
    _udpPeriodicPingTimer?.cancel();
    _udpPeriodicPingTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    _isSearching = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _udpPeriodicPingTimer?.cancel();
    _udpSocket?.close();
    stopDiscovery();
    super.dispose();
  }
}
