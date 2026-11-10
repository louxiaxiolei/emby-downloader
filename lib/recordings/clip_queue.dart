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

class ClipException implements Exception {
  ClipException(this.message);

  final String message;

  @override
  String toString() => message;
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
        throw ClipException('片段太短');
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
        throw ClipException('片段文件是空的（${bytes}B）');
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

/// A second libmpv, started only for this clip. It never touches the player
/// that is on screen.
///
/// media_kit creates that player with `vid=no` and never attaches a video
/// view. `stream-record` then stays at 0 bytes even after `loadfile` seeks to
/// the range and plays it: the demuxer does not start its recorder for this
/// setup. `dump-cache` writes the packets this player already read, including
/// the video track, once playback reaches [end].
Future<int> captureStreamRange({
  required String url,
  required String output,
  required Map<String, String> headers,
  required Duration start,
  required Duration end,
  required void Function(double progress) onProgress,
}) async {
  final player = Player(
    configuration: const PlayerConfiguration(vo: 'null', muted: true, bufferSize: 32 * 1024 * 1024),
  );
  final errors = <String>[];
  StreamSubscription<String>? errorSub;
  try {
    final native = player.platform;
    if (native is! NativePlayer) {
      throw ClipException('没有 mpv，不能生成片段');
    }
    final existing = File(output);
    if (await existing.exists()) await existing.delete();
    // The on-screen player already owns the audio device. This one only reads.
    await native.setProperty('ao', 'null');
    await native.setProperty('vid', 'auto');
    await native.setProperty('aid', 'auto');
    await native.setProperty('cache', 'yes');
    await native.setProperty('cache-on-disk', 'no');
    final cache = _clipCacheMebibytes(end - start);
    await native.setProperty('demuxer-max-bytes', '${cache}MiB');
    await native.setProperty('demuxer-max-back-bytes', '${cache}MiB');
    await native.setProperty('network-timeout', '60');
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'accept') continue;
      await native.command([
        'change-list',
        'http-header-fields',
        'append',
        '${entry.key}: ${entry.value}',
      ]);
    }
    errorSub = player.stream.error.listen((message) {
      errors.add(message);
      NetLog.instance.add('片段 mpv 错误 $message');
    });
    final target = Uri.tryParse(url);
    final loadUrl = target != null && target.isScheme('file') ? target.toFilePath() : url;
    NetLog.instance.add('片段开始 ${NetLog.redact(Uri.parse(url))} ${mpvSeconds(start)}-${mpvSeconds(end)}');
    await native.command([
      'loadfile',
      loadUrl,
      'replace',
      'start=${mpvSeconds(start)},end=${mpvSeconds(end)}',
    ]);
    await native.setProperty('pause', 'no');

    final spanMs = (end - start).inMilliseconds.clamp(1, 1 << 31);
    final deadline = DateTime.now().add(end - start + const Duration(minutes: 3));
    var position = Duration.zero;
    while (DateTime.now().isBefore(deadline)) {
      final seconds = double.tryParse(await native.getProperty('time-pos'));
      if (seconds != null) {
        position = Duration(milliseconds: (seconds * 1000).round());
        final doneMs = position - start;
        onProgress((doneMs.inMilliseconds / spanMs).clamp(0.0, 1.0));
      }
      final eof = await native.getProperty('eof-reached');
      if (eof == 'yes' || eof == 'true') break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await native.command(['dump-cache', mpvSeconds(start), mpvSeconds(end), output]);
    final size = await _fileSize(output);
    NetLog.instance.add('片段写出 ${size}B 停在 ${formatClock(position)} $output');
    if (size < 1024) {
      final detail = errors.isEmpty
          ? '没有生成视频文件（${size}B，停在 ${formatClock(position)}）'
          : errors.join(' ');
      throw ClipException(detail);
    }
    onProgress(1);
    return size;
  } finally {
    await errorSub?.cancel();
    await player.dispose();
  }
}

/// Enough demuxer cache for this clip on the background player only.
int _clipCacheMebibytes(Duration span) {
  final seconds = span.inMilliseconds / 1000;
  final estimate = (seconds * 8).ceil();
  if (estimate < 32) return 32;
  if (estimate > 160) return 160;
  return estimate;
}

Future<int> _fileSize(String path) async {
  final file = File(path);
  if (!await file.exists()) return 0;
  return file.length();
}
