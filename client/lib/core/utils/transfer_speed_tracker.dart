/// Smooth real-time transfer speed calculator (MB/s or KB/s)
class TransferSpeedTracker {
  DateTime _lastTime = DateTime.now();
  int _lastBytes = 0;
  double _smoothSpeedBps = 0.0;

  void reset() {
    _lastTime = DateTime.now();
    _lastBytes = 0;
    _smoothSpeedBps = 0.0;
  }

  void update(int currentBytes) {
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastTime).inMilliseconds;
    if (elapsedMs >= 200) {
      final bytesDiff = currentBytes - _lastBytes;
      if (bytesDiff >= 0) {
        final instantSpeed = bytesDiff / (elapsedMs / 1000.0);
        if (_smoothSpeedBps == 0.0) {
          _smoothSpeedBps = instantSpeed;
        } else {
          // Exponential moving average for jitter-free display
          _smoothSpeedBps = (_smoothSpeedBps * 0.65) + (instantSpeed * 0.35);
        }
      }
      _lastTime = now;
      _lastBytes = currentBytes;
    }
  }

  String get formattedSpeed {
    if (_smoothSpeedBps <= 0) return '0 KB/s';
    final mbps = _smoothSpeedBps / (1024 * 1024);
    if (mbps >= 1.0) {
      return '${mbps.toStringAsFixed(1)} MB/s';
    }
    final kbps = _smoothSpeedBps / 1024;
    return '${kbps.toStringAsFixed(0)} KB/s';
  }
}
