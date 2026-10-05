import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/network/api_client.dart';

class ServerSidecarController extends ChangeNotifier {
  Process? _process;
  bool _isRunning = false;
  bool _isStarting = false;
  String _storagePath;
  int _port;
  String _serverStatus = 'Stopped';
  String _localIp = '127.0.0.1';
  Map<String, dynamic>? _diskMetrics;
  final List<String> _logs = [];
  Timer? _metricsTimer;
  late final ApiClient _apiClient;

  bool get isRunning => _isRunning;
  bool get isStarting => _isStarting;
  String get storagePath => _storagePath;
  int get port => _port;
  String get serverStatus => _serverStatus;
  String get localIp => _localIp;
  Map<String, dynamic>? get diskMetrics => _diskMetrics;
  List<String> get logs => List.unmodifiable(_logs);

  ServerSidecarController({
    String? initialStoragePath,
    int initialPort = 8080,
  })  : _storagePath = initialStoragePath ?? '',
        _port = initialPort {
    _apiClient = ApiClient(baseUrl: 'http://127.0.0.1:$_port/api/v1');
    _detectLocalIp();
  }

  void _addLog(String line) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final formatted = '[$timestamp] $line';
    _logs.insert(0, formatted);
    if (_logs.length > 200) {
      _logs.removeLast();
    }
    notifyListeners();
  }

  Future<void> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            _localIp = addr.address;
            notifyListeners();
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[ServerSidecar] IP detection error: $e');
    }
  }

  void setStoragePath(String newPath) {
    _storagePath = newPath;
    notifyListeners();
  }

  void setPort(int newPort) {
    _port = newPort;
    _apiClient.updateBaseUrl('http://127.0.0.1:$_port/api/v1');
    notifyListeners();
  }

  /// Locates the compiled server binary depending on platform
  Future<String> _resolveBinaryPath() async {
    String binaryName;
    if (Platform.isWindows) {
      binaryName = 'server.exe';
    } else if (Platform.isMacOS) {
      binaryName = 'server_mac';
    } else {
      binaryName = 'server_linux';
    }

    // 1. Look in application support / assets directory
    final appDir = await getApplicationSupportDirectory();
    final localBin = p.join(appDir.path, 'bin', binaryName);
    if (await File(localBin).exists()) {
      return localBin;
    }

    // 2. Look in relative assets/bin or executable path directory
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidatePaths = [
      p.join(exeDir, 'assets', 'bin', binaryName),
      p.join(exeDir, binaryName),
      p.join(Directory.current.path, 'assets', 'bin', binaryName),
      p.join(Directory.current.path, '..', 'server', binaryName),
      p.join(Directory.current.path, '..', 'server', 'cmd', 'api', binaryName),
    ];

    for (final path in candidatePaths) {
      if (await File(path).exists()) {
        return path;
      }
    }

    // Fallback to binary name in PATH
    return binaryName;
  }

  /// Starts the Go auto-backup daemon
  Future<bool> startServer() async {
    if (_isRunning || _isStarting) return true;

    _isStarting = true;
    _serverStatus = 'Starting...';
    notifyListeners();

    try {
      if (_storagePath.isEmpty) {
        final docs = await getApplicationDocumentsDirectory();
        _storagePath = p.join(docs.path, 'SamConnectedStorage');
      }

      await Directory(_storagePath).create(recursive: true);

      final binaryPath = await _resolveBinaryPath();
      _addLog('Memulai server sidecar dari: $binaryPath');
      _addLog('Storage directory: $_storagePath');

      final args = [
        '-port', '$_port',
        '-storage', _storagePath,
        '-mdns-name', 'SamConnectedHost',
      ];

      _process = await Process.start(
        binaryPath,
        args,
        mode: ProcessStartMode.normal,
      );

      _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _addLog('[ENGINE] $line');
      });

      _process!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _addLog('[ENGINE-ERR] $line');
      });

      _process!.exitCode.then((code) {
        _isRunning = false;
        _isStarting = false;
        _serverStatus = 'Stopped (exit code: $code)';
        _addLog('Proses server berhenti dengan kode: $code');
        _metricsTimer?.cancel();
        notifyListeners();
      });

      // Poll ping endpoint until healthy
      final ready = await _pollHealth(retries: 25, intervalMs: 200);
      if (ready) {
        _isRunning = true;
        _isStarting = false;
        _serverStatus = 'Running';
        _addLog('Server berjalan normal pada http://$_localIp:$_port/api/v1');
        _startMetricsPolling();
        notifyListeners();
        return true;
      } else {
        _serverStatus = 'Failed to respond';
        _isStarting = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isRunning = false;
      _isStarting = false;
      _serverStatus = 'Error: $e';
      _addLog('Gagal menjalankan binary server: $e');
      notifyListeners();
      return false;
    }
  }

  Future<bool> _pollHealth({int retries = 25, int intervalMs = 200}) async {
    for (int i = 0; i < retries; i++) {
      await Future.delayed(Duration(milliseconds: intervalMs));
      try {
        final res = await _apiClient.ping();
        if (res['status'] == 'ok') {
          _diskMetrics = res['disk'] as Map<String, dynamic>?;
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  void _startMetricsPolling() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isRunning) return;
      try {
        final res = await _apiClient.ping();
        _diskMetrics = res['disk'] as Map<String, dynamic>?;
        notifyListeners();
      } catch (_) {}
    });
  }

  /// Terminates daemon process
  Future<void> stopServer() async {
    _metricsTimer?.cancel();
    if (_process != null) {
      _addLog('Mengirim sinyal SIGTERM ke proses server...');
      _process!.kill(ProcessSignal.sigterm);
      await Future.delayed(const Duration(milliseconds: 500));
      _process = null;
    }
    _isRunning = false;
    _isStarting = false;
    _serverStatus = 'Stopped';
    notifyListeners();
  }

  @override
  void dispose() {
    stopServer();
    super.dispose();
  }
}
