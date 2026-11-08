/// Transfer rate measured from byte totals, not from the downloader's own estimate.
///
/// background_downloader on iOS seeds its clock at the Unix epoch and then
/// smooths speed with a 3:1 average. A short URLSession burst can stick in that
/// average, which is how a ~12 MB/s transfer was shown as 108 MB/s (and the
/// remaining time, derived from that speed, shrank by the same factor).
/// This tracker uses the bytes implied by `progress * Content-Length` over a
/// several-second window instead.
class SpeedEstimate {
  const SpeedEstimate({required this.bytesPerSecond, this.remaining});

  final double bytesPerSecond;
  final Duration? remaining;
}

class SpeedTracker {
  final List<(DateTime at, int bytes)> _samples = [];

  SpeedEstimate? addSample({
    required DateTime at,
    required int bytes,
    int? totalBytes,
  }) {
    if (bytes < 0) return null;
    if (_samples.isNotEmpty && bytes < _samples.last.$2) {
      _samples
        ..clear()
        ..add((at, bytes));
      return null;
    }
    _samples.add((at, bytes));
    final cutoff = at.subtract(const Duration(seconds: 6));
    while (_samples.length > 2 && _samples.first.$1.isBefore(cutoff)) {
      _samples.removeAt(0);
    }
    final span = _samples.last.$1.difference(_samples.first.$1);
    if (span < const Duration(milliseconds: 1000)) return null;
    final delta = _samples.last.$2 - _samples.first.$2;
    if (delta < 0) return null;
    final rate = delta / (span.inMicroseconds / 1000000);
    Duration? remaining;
    if (totalBytes != null && totalBytes > bytes && rate > 1) {
      remaining = Duration(microseconds: ((totalBytes - bytes) / rate * 1000000).round());
    }
    return SpeedEstimate(bytesPerSecond: rate, remaining: remaining);
  }
}

String formatTransferSpeed(double bytesPerSecond) {
  if (bytesPerSecond.isNaN || bytesPerSecond.isInfinite || bytesPerSecond < 0) return '';
  if (bytesPerSecond >= 1000000) {
    return '${(bytesPerSecond / 1000000).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1000) {
    return '${(bytesPerSecond / 1000).toStringAsFixed(0)} KB/s';
  }
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}

String formatClock(Duration duration) {
  final total = duration.inSeconds.clamp(0, 99 * 3600);
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
  return '${two(minutes)}:${two(seconds)}';
}

/// Label for a downloader progress fraction.
///
/// `0` is the plugin's "just started" value, before Content-Length has produced
/// a real fraction. Showing that as `0%` made the track look stuck. Negative
/// values mean the size is unknown (or the task failed).
String progressLabel(double progress) {
  if (progress.isNaN || progress < 0) return '大小未知';
  if (progress <= 0) return '准备中';
  if (progress < 0.01) return '<1%';
  if (progress >= 1) return '100%';
  return '${(progress * 100).round()}%';
}

/// `null` is an indeterminate bar (size unknown). `0` is an empty bar.
double? progressBarValue(double progress) {
  if (progress.isNaN || progress < 0) return null;
  if (progress <= 0) return 0;
  return progress.clamp(0.0, 1.0);
}
