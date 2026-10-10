// Utility formatters for files, dates, and network statistics.

String formatBytes(dynamic bytes) {
  if (bytes == null) return '0 B';
  final int b = (bytes is int) ? bytes : (bytes as num).toInt();
  if (b <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  int i = 0;
  double count = b.toDouble();
  while (count >= 1024 && i < suffixes.length - 1) {
    count /= 1024;
    i++;
  }
  return '${count.toStringAsFixed(1)} ${suffixes[i]}';
}
