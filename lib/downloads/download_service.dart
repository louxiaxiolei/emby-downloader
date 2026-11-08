import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../emby/api.dart';
import '../emby/models.dart';
import '../emby/plan.dart';
import '../emby/urls.dart';
import '../storage/settings_store.dart';

const kDownloadGroup = 'emby';

class LocalFile {
  const LocalFile({
    required this.taskId,
    required this.itemId,
    required this.kind,
    required this.title,
    required this.filename,
    required this.directory,
    required this.savedAt,
    this.sharedPath,
    this.bytes,
  });

  final String taskId;
  final String itemId;
  final String kind;
  final String title;
  final String filename;
  final String directory;
  final String savedAt;
  final String? sharedPath;
  final int? bytes;

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'itemId': itemId,
    'kind': kind,
    'title': title,
    'filename': filename,
    'directory': directory,
    'savedAt': savedAt,
    'sharedPath': sharedPath,
    'bytes': bytes,
  };

  factory LocalFile.fromJson(Map<String, dynamic> json) {
    return LocalFile(
      taskId: json['taskId'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      kind: json['kind'] as String? ?? 'video',
      title: json['title'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      directory: json['directory'] as String? ?? '',
      savedAt: json['savedAt'] as String? ?? '',
      sharedPath: json['sharedPath'] as String?,
      bytes: (json['bytes'] as num?)?.toInt(),
    );
  }
}

class LiveDownload {
  LiveDownload({
    required this.task,
    required this.status,
    this.progress = 0,
    this.speedLabel,
    this.remainingLabel,
    this.httpStatus,
    this.error,
  });

  final DownloadTask task;
  TaskStatus status;
  double progress;
  String? speedLabel;
  String? remainingLabel;
  int? httpStatus;
  String? error;

  DownloadMeta get meta => DownloadMeta.decode(task.metaData);

  bool get active =>
      status == TaskStatus.enqueued ||
      status == TaskStatus.running ||
      status == TaskStatus.paused ||
      status == TaskStatus.waitingToRetry;
}

class EnqueueResult {
  const EnqueueResult({required this.enqueued, required this.skipped, this.message});

  final int enqueued;
  final int skipped;
  final String? message;
}

class DownloadService extends ChangeNotifier {
  DownloadService(this.settings);

  final SettingsStore settings;
  final List<LiveDownload> live = [];
  final List<LocalFile> files = [];
  String? initError;
  StreamSubscription<TaskUpdate>? _subscription;
  var _ready = false;

  int get activeCount => live.where((item) => item.active).length;

  Future<void> init() async {
    if (_ready) return;
    await _loadCatalog();
    try {
      FileDownloader().configureNotification(
        running: const TaskNotification('正在下载', '{displayName}'),
        complete: const TaskNotification('下载完成', '{displayName}'),
        error: const TaskNotification('下载失败', '{displayName}'),
        paused: const TaskNotification('已暂停', '{displayName}'),
        progressBar: true,
      );
      await FileDownloader().configure(
        globalConfig: [
          (Config.requestTimeout, const Duration(seconds: 60)),
          (Config.resourceTimeout, const Duration(hours: 24)),
          (Config.holdingQueue, (2, 2, null)),
          (Config.useCacheDir, Config.never),
        ],
        androidConfig: [
          (Config.runInForeground, Config.always),
        ],
        iOSConfig: [
          (Config.localize, {'Cancel': '取消', 'Pause': '暂停', 'Resume': '继续'}),
          (Config.excludeFromCloudBackup, Config.always),
        ],
      );
      _subscription = FileDownloader().updates.listen((update) {
        unawaited(_handle(update));
      });
      await FileDownloader().start();
      await _absorbRecords();
      _ready = true;
    } catch (error) {
      initError = '下载器没有启动：$error';
    }
    notifyListeners();
  }

  Future<EnqueueResult> enqueueItem({
    required EmbyClient client,
    required EmbyItem item,
    EmbyMediaSource? source,
  }) {
    return _enqueueAll(client, [item], preferred: {item.id: source});
  }

  Future<EnqueueResult> enqueueEpisodes({
    required EmbyClient client,
    required List<EmbyItem> episodes,
  }) {
    return _enqueueAll(client, episodes);
  }

  Future<void> pause(DownloadTask task) async {
    await FileDownloader().pause(task);
  }

  Future<void> resume(DownloadTask task) async {
    await FileDownloader().resume(task);
  }

  Future<void> cancel(LiveDownload item) async {
    await FileDownloader().cancelTasksWithIds([item.task.taskId]);
  }

  Future<void> dismiss(LiveDownload item) async {
    await FileDownloader().database.deleteRecordWithId(item.task.taskId);
    live.removeWhere((entry) => entry.task.taskId == item.task.taskId);
    notifyListeners();
  }

  Future<void> retry(LiveDownload item) async {
    await FileDownloader().database.deleteRecordWithId(item.task.taskId);
    live.removeWhere((entry) => entry.task.taskId == item.task.taskId);
    final ok = await FileDownloader().enqueue(item.task);
    if (!ok) {
      item.error = '无法重新加入队列';
      live.add(item);
    }
    notifyListeners();
  }

  Future<String?> openFile(LocalFile file) async {
    final path = file.sharedPath ?? await _appPath(file);
    if (path.startsWith('content:')) {
      final opened = await FileDownloader().uri.openFile(
        Uri.parse(path),
        mimeType: mimeForFilename(file.filename),
      );
      return opened ? null : '没有可以打开这个文件的应用';
    }
    final result = await OpenFilex.open(path, type: mimeForFilename(file.filename));
    if (result.type == ResultType.done) return null;
    return '无法打开。文件在「${file.directory}/${file.filename}」';
  }

  Future<void> deleteItem(String itemId) async {
    final pending = live.where((entry) => entry.meta.itemId == itemId).toList();
    if (pending.isNotEmpty) {
      await FileDownloader().cancelTasksWithIds([
        for (final entry in pending) entry.task.taskId,
      ]);
      live.removeWhere((entry) => entry.meta.itemId == itemId);
    }
    final saved = files.where((file) => file.itemId == itemId).toList();
    for (final file in saved) {
      await _deleteLocal(file);
    }
    files.removeWhere((file) => file.itemId == itemId);
    await _saveCatalog();
    notifyListeners();
  }

  bool hasVideo(String itemId) {
    if (files.any((file) => file.itemId == itemId && file.kind == 'video')) {
      return true;
    }
    return live.any(
      (entry) =>
          entry.meta.itemId == itemId &&
          entry.meta.kind == 'video' &&
          entry.active,
    );
  }

  Future<EnqueueResult> _enqueueAll(
    EmbyClient client,
    List<EmbyItem> items, {
    Map<String, EmbyMediaSource?> preferred = const {},
  }) async {
    await _ensureNotificationPermission();
    final used = <String>{
      for (final file in files) '${file.directory}/${file.filename}',
      for (final entry in live) '${entry.task.directory}/${entry.task.filename}',
    };
    final names = <String>{
      for (final name in used) name.split('/').last,
    };
    var enqueued = 0;
    var skipped = 0;
    for (final item in items) {
      if (!item.canDownload) {
        skipped++;
        continue;
      }
      if (hasVideo(item.id)) {
        skipped++;
        continue;
      }
      live.removeWhere(
        (entry) =>
            entry.meta.itemId == item.id &&
            (entry.status == TaskStatus.failed || entry.status == TaskStatus.notFound),
      );
      final source = preferred[item.id] ??
          (item.mediaSources.isEmpty ? null : item.mediaSources.first);
      final plans = planItemDownload(
        apiRoot: client.session.apiRoot,
        accessToken: client.session.accessToken,
        item: item,
        source: source,
        usedNames: names,
      );
      for (final plan in plans) {
        final task = _task(plan, client);
        final ok = await FileDownloader().enqueue(task);
        if (ok) {
          live.add(LiveDownload(task: task, status: TaskStatus.enqueued));
          enqueued++;
        }
      }
    }
    notifyListeners();
    return EnqueueResult(enqueued: enqueued, skipped: skipped);
  }

  DownloadTask _task(PlannedDownload plan, EmbyClient client) {
    final meta = DownloadMeta(
      kind: plan.kind,
      itemId: plan.itemId,
      title: plan.title,
      stage: 0,
      urls: plan.urls,
    );
    return DownloadTask(
      taskId: const Uuid().v4(),
      url: plan.urls.first,
      filename: plan.filename,
      directory: plan.directory,
      baseDirectory: BaseDirectory.applicationDocuments,
      group: kDownloadGroup,
      updates: Updates.statusAndProgress,
      requiresWiFi: settings.wifiOnly,
      retries: 2,
      allowPause: true,
      displayName: plan.displayName,
      metaData: meta.encode(),
      headers: {
        'X-Emby-Token': client.session.accessToken,
        'X-Emby-Authorization': embyAuthorizationHeader(
          client: client.clientName,
          deviceId: client.deviceId,
          userId: client.session.userId,
        ),
      },
    );
  }

  Future<void> _handle(TaskUpdate update) async {
    if (update.task.group != kDownloadGroup || update.task is! DownloadTask) {
      return;
    }
    final task = update.task as DownloadTask;
    switch (update) {
      case TaskStatusUpdate status:
        await _onStatus(task, status);
      case TaskProgressUpdate progress:
        final entry = _find(task.taskId);
        if (entry == null) return;
        entry.progress = progress.progress;
        entry.speedLabel = progress.hasNetworkSpeed ? progress.networkSpeedAsString : null;
        entry.remainingLabel = progress.hasTimeRemaining
            ? progress.timeRemainingAsString
            : null;
        notifyListeners();
    }
  }

  Future<void> _onStatus(DownloadTask task, TaskStatusUpdate update) async {
    final entry = _find(task.taskId) ?? LiveDownload(task: task, status: update.status);
    if (_find(task.taskId) == null &&
        update.status != TaskStatus.complete &&
        update.status != TaskStatus.canceled) {
      live.add(entry);
    }
    entry.status = update.status;
    entry.httpStatus = update.responseStatusCode;
    entry.error = update.exception?.description;
    if (update.status == TaskStatus.complete) {
      await _archive(task);
      await FileDownloader().database.deleteRecordWithId(task.taskId);
      live.removeWhere((item) => item.task.taskId == task.taskId);
      notifyListeners();
      return;
    }
    if (update.status == TaskStatus.canceled) {
      live.removeWhere((item) => item.task.taskId == task.taskId);
      await FileDownloader().database.deleteRecordWithId(task.taskId);
      notifyListeners();
      return;
    }
    if (update.status == TaskStatus.failed || update.status == TaskStatus.notFound) {
      final switched = await _tryFallback(task, update);
      if (switched) {
        live.removeWhere((item) => item.task.taskId == task.taskId);
        await FileDownloader().database.deleteRecordWithId(task.taskId);
      }
    }
    notifyListeners();
  }

  Future<bool> _tryFallback(DownloadTask task, TaskStatusUpdate update) async {
    final meta = DownloadMeta.decode(task.metaData);
    if (meta.kind != 'video') return false;
    final code = update.responseStatusCode ??
        (update.exception is TaskHttpException
            ? (update.exception! as TaskHttpException).httpResponseCode
            : null);
    final recoverable = update.status == TaskStatus.notFound ||
        code == 400 ||
        code == 403 ||
        code == 404;
    if (!recoverable) return false;
    final nextStage = meta.stage + 1;
    if (nextStage >= meta.urls.length) return false;
    final next = task.copyWith(
      taskId: const Uuid().v4(),
      url: meta.urls[nextStage],
      metaData: meta.copyWith(stage: nextStage).encode(),
    );
    live.add(LiveDownload(task: next, status: TaskStatus.enqueued));
    return FileDownloader().enqueue(next);
  }

  Future<void> _archive(DownloadTask task) async {
    if (files.any((file) => file.taskId == task.taskId)) return;
    final meta = DownloadMeta.decode(task.metaData);
    String? shared;
    if (!kIsWeb && Platform.isAndroid && settings.publicDownloads) {
      try {
        await _ensureSharedStoragePermission();
        shared = await FileDownloader().moveToSharedStorage(
          task,
          SharedStorage.downloads,
          directory: task.directory,
          mimeType: mimeForFilename(task.filename),
        );
      } catch (_) {
        shared = null;
      }
    }
    int? bytes;
    final path = shared ?? await task.filePath();
    if (!path.startsWith('content:')) {
      final file = File(path);
      if (await file.exists()) bytes = await file.length();
    }
    files.insert(
      0,
      LocalFile(
        taskId: task.taskId,
        itemId: meta.itemId,
        kind: meta.kind,
        title: meta.title.isEmpty ? task.displayName : meta.title,
        filename: task.filename,
        directory: task.directory,
        savedAt: DateTime.now().toIso8601String(),
        sharedPath: shared,
        bytes: bytes,
      ),
    );
    await _saveCatalog();
  }

  Future<void> _absorbRecords() async {
    final records = await FileDownloader().database.allRecords(group: kDownloadGroup);
    for (final record in records) {
      if (record.task is! DownloadTask) continue;
      final task = record.task as DownloadTask;
      if (record.status == TaskStatus.complete) {
        await _archive(task);
        await FileDownloader().database.deleteRecordWithId(task.taskId);
        continue;
      }
      if (record.status == TaskStatus.canceled) {
        await FileDownloader().database.deleteRecordWithId(task.taskId);
        continue;
      }
      if (_find(task.taskId) != null) continue;
      live.add(
        LiveDownload(
          task: task,
          status: record.status,
          progress: record.progress < 0 ? 0 : record.progress,
          error: record.exception?.description,
        ),
      );
    }
  }

  LiveDownload? _find(String taskId) {
    for (final entry in live) {
      if (entry.task.taskId == taskId) return entry;
    }
    return null;
  }

  Future<void> _ensureNotificationPermission() async {
    final status = await FileDownloader().permissions.status(PermissionType.notifications);
    if (status == PermissionStatus.granted) return;
    await FileDownloader().permissions.request(PermissionType.notifications);
  }

  Future<void> _ensureSharedStoragePermission() async {
    final status = await FileDownloader().permissions.status(
      PermissionType.androidSharedStorage,
    );
    if (status == PermissionStatus.granted) return;
    await FileDownloader().permissions.request(PermissionType.androidSharedStorage);
  }

  Future<File> _catalogFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'emby_catalog.json'));
  }

  Future<void> _loadCatalog() async {
    try {
      final file = await _catalogFile();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! List) return;
      files
        ..clear()
        ..addAll([
          for (final item in json)
            if (item is Map) LocalFile.fromJson(Map<String, dynamic>.from(item)),
        ]);
    } catch (_) {
      // A damaged catalog should not block new downloads.
    }
  }

  Future<void> _saveCatalog() async {
    final file = await _catalogFile();
    await file.writeAsString(jsonEncode([for (final item in files) item.toJson()]));
  }

  Future<String> _appPath(LocalFile file) async {
    final root = await getApplicationDocumentsDirectory();
    return p.join(root.path, file.directory, file.filename);
  }

  Future<void> _deleteLocal(LocalFile file) async {
    final path = file.sharedPath ?? await _appPath(file);
    if (path.startsWith('content:') || path.startsWith('file:')) {
      await FileDownloader().uri.deleteFile(Uri.parse(path));
      return;
    }
    final target = File(path);
    if (await target.exists()) await target.delete();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
