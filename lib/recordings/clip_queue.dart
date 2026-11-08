import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../downloads/speed.dart';
import '../emby/net_log.dart';
import '../ui/messenger.dart';
import 'clip.dart';
import 'names.dart';
import 'remux.dart';
import 'store.dart';

enum ClipJobState { running, failed, saved }

class ClipJob {
  ClipJob({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
  });

  final int id;
  final String title;
  final Duration start;
  final Duration end;
  ClipJobState state = ClipJobState.running;
  double progress = 0;
  String message = '正在生成片段…';
  String? path;
}

class ClipRequest {
  const ClipRequest({
    required this.title,
    required this.sourceUrl,
    required this.headers,
    required this.start,
    required this.end,
    required this.saveToPhotos,
    this.episode,
  });

  final String title;
  final String? episode;
  final String sourceUrl;
  final Map<String, String> headers;
  final Duration start;
  final Duration end;
  final bool saveToPhotos;
}

/// Background clip jobs. They never touch the player that is on screen.
class ClipQueue extends ChangeNotifier {
  ClipQueue._();

  static final instance = ClipQueue._();

  final List<ClipJob> jobs = [];

  void dismiss(int id) {
    jobs.removeWhere((job) => job.id == id);
    notifyListeners();
  }

  void enqueue(ClipRequest request) {
    final job = ClipJob(
      id: DateTime.now().microsecondsSinceEpoch,
      title: request.title,
      start: request.start,
      end: request.end,
    );
    jobs.insert(0, job);
    notifyListeners();
    NetLog.instance.add(
      '排队生成片段 ${request.title} ${formatClock(request.start)}-${formatClock(request.end)}',
    );
    unawaited(_run(job, request));
  }

  Future<void> _run(ClipJob job, ClipRequest request) async {
    try {
      if (!recordSpanIsUsable(request.start, request.end)) {
        throw StateError('片段太短');
      }
      final directory = await recordingsDirectory();
      final temp = p.join(directory.path, 'clip-${job.id}.mkv');
      final bytes = await captureStreamRange(
        url: request.sourceUrl,
        output: temp,
        headers: request.headers,
        start: request.start,
        end: request.end,
        onProgress: (progress) {
          job.progress = progress;
          job.message = '正在生成片段… ${(progress * 100).round()}%';
          notifyListeners();
        },
      );
      NetLog.instance.add('片段文件 ${bytes}B $temp');
      if (bytes < 1024) {
        throw StateError('片段文件是空的（${bytes}B）');
      }
      final name = recordingFileName(
        title: request.title,
        episode: request.episode,
        start: request.start,
        end: request.end,
        extension: 'mkv',
      );
      var dest = p.join(directory.path, name);
      if (await File(dest).exists()) {
        dest = p.join(directory.path, '${p.basenameWithoutExtension(name)}-${job.id}.mkv');
      }
      await File(temp).rename(dest);
      job.path = dest;
      job.progress = 1;
      job.state = ClipJobState.saved;
      job.message = '已生成 ${p.basename(dest)}';
      NetLog.instance.add('片段已保存 ${await File(dest).length()}B $dest');
      notifyListeners();
      _tell(job.message);
      if (request.saveToPhotos) {
        try {
          final photos = await saveRecordingToPhotos(dest);
          NetLog.instance.add('片段自动保存到相册 $photos');
          _tell('$photos，下载页仍保留这份文件');
        } catch (error) {
          NetLog.instance.add('片段自动保存到相册失败 $error');
          _tell('文件已留在录制列表，写入相册失败：$error');
        }
      }
    } catch (error) {
      job.state = ClipJobState.failed;
      job.message = '$error';
      NetLog.instance.add('生成片段失败 $error');
      notifyListeners();
      _tell('生成片段失败：$error');
    }
  }

  void _tell(String message) {
    final messenger = scaffoldMessengerKey.currentState;
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// A second libmpv, started only for this clip. `stream-record` is set before
/// the file opens, so it writes the packets this process actually reads.
Future<int> captureStreamRange({
  required String url,
  required String output,
  required Map<String, String> headers,
  required Duration start,
  required Duration end,
  required void Function(double progress) onProgress,
}) async {
  final player = Player(
    configuration: const PlayerConfiguration(vo: 'null', muted: true, bufferSize: 8 * 1024 * 1024),
  );
  final errors = <String>[];
  StreamSubscription<bool>? completedSub;
  StreamSubscription<String>? errorSub;
  StreamSubscription<Duration>? positionSub;
  try {
    final native = player.platform;
    if (native is! NativePlayer) {
      throw StateError('没有 mpv，不能生成片段');
    }
    final existing = File(output);
    if (await existing.exists()) await existing.delete();
    await native.setProperty('stream-record', output);
    await native.setProperty('demuxer-max-bytes', '8MiB');
    await native.setProperty('demuxer-readahead-secs', '2');
    await native.setProperty('demuxer-max-back-bytes', '8MiB');
    final done = Completer<void>();
    completedSub = player.stream.completed.listen((value) {
      if (value && !done.isCompleted) done.complete();
    });
    errorSub = player.stream.error.listen((message) {
      errors.add(message);
      NetLog.instance.add('片段 mpv 错误 $message');
    });
    final spanMs = (end - start).inMilliseconds.clamp(1, 1 << 31);
    positionSub = player.stream.position.listen((position) {
      final doneMs = position - start;
      final progress = (doneMs.inMilliseconds / spanMs).clamp(0.0, 1.0);
      onProgress(progress);
    });
    await player.open(
      Media(
        url,
        httpHeaders: headers.isEmpty ? null : headers,
        start: start,
        end: end,
      ),
    );
    await player.play();
    try {
      await done.future.timeout(end - start + const Duration(minutes: 2));
    } on TimeoutException {
      NetLog.instance.add('片段等待结束超时，仍检查已写出的文件');
    }
    await native.setProperty('stream-record', '');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final file = File(output);
    final size = await file.exists() ? await file.length() : 0;
    if (size < 1024) {
      final detail = errors.isEmpty ? '没有写出文件' : errors.join(' ');
      throw StateError(detail);
    }
    onProgress(1);
    return size;
  } finally {
    await completedSub?.cancel();
    await errorSub?.cancel();
    await positionSub?.cancel();
    await player.dispose();
  }
}
