import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Human readable byte sizes, e.g. `1.42 GB`.
String formatBytes(num? bytes, {int decimals = 2}) {
  if (bytes == null || bytes <= 0) return '0 B';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  final int digitGroups = math
      .max(0, (math.log(bytes.toDouble()) / math.log(1024)).floor())
      .clamp(0, units.length - 1);
  final double value = bytes / math.pow(1024, digitGroups).toDouble();
  final NumberFormat fmt = NumberFormat.decimalPattern()
    ..maximumFractionDigits = digitGroups == 0 ? 0 : decimals;
  return '${fmt.format(value)} ${units[digitGroups]}';
}

/// `95` → `1h 35m`; `42` → `42m`.
String formatRuntime(int? minutes) {
  if (minutes == null || minutes <= 0) return '—';
  final int hours = minutes ~/ 60;
  final int mins = minutes % 60;
  if (hours == 0) return '${mins}m';
  return '${hours}h ${mins.toString().padLeft(2, '0')}m';
}

/// Seconds → `1:23:45` or `12:34`.
String formatDuration(num? totalSeconds) {
  if (totalSeconds == null || totalSeconds < 0) return '--:--';
  final int seconds = totalSeconds.round();
  final int h = seconds ~/ 3600;
  final int m = (seconds % 3600) ~/ 60;
  final int s = seconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// `2543210` → `2.5 MB/s`.
String formatSpeed(num bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

/// Compact counts: `1234567` → `1.2M`, `2543` → `2.5K`.
String formatCompact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

/// Percentage of progress in `0–100` with one decimal, e.g. `42.7%`.
String formatProgress(double fraction) {
  final double clamped = fraction.clamp(0.0, 1.0);
  return '${(clamped * 100).toStringAsFixed(clamped >= 0.995 ? 0 : 1)}%';
}
