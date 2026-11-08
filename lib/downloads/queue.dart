/// A download row the queue can dedupe without depending on the plugin.
class TrackedDownload {
  TrackedDownload({
    required this.taskId,
    required this.itemId,
    required this.kind,
    required this.status,
  });

  final String taskId;
  final String itemId;
  final String kind;
  String status;

  bool get active =>
      status == 'enqueued' || status == 'running' || status == 'paused' || status == 'waiting';
}

/// One row per task id. A later status for the same id updates the existing row.
///
/// The downloads page was adding a row when `enqueue` returned and again when
/// the status callback arrived first, so one tap showed two cards for one task:
/// the updated one "下载中" and the second stuck on "等待中".
TrackedDownload upsertDownload(List<TrackedDownload> items, TrackedDownload incoming) {
  for (final item in items) {
    if (item.taskId == incoming.taskId) {
      item.status = incoming.status;
      return item;
    }
  }
  items.add(incoming);
  return incoming;
}

/// True when this Emby item should not be queued again.
///
/// A saved video, an active video row, or an enqueue already in flight all count.
bool itemAlreadyQueued({
  required String itemId,
  required Iterable<TrackedDownload> live,
  required Iterable<String> savedVideoItemIds,
  required Set<String> inFlightItemIds,
}) {
  if (itemId.isEmpty) return false;
  if (inFlightItemIds.contains(itemId)) return true;
  if (savedVideoItemIds.contains(itemId)) return true;
  return live.any((item) => item.itemId == itemId && item.kind == 'video' && item.active);
}
