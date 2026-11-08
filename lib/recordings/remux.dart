import 'dart:async';
import 'dart:io';

import 'package:gal/gal.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../emby/net_log.dart';
import 'photos_plan.dart';

class ProbeCodecs {
  const ProbeCodecs({required this.video, required this.audio});

  final String video;
  final String audio;
}

/// Read codec names from a local file with a headless mpv instance.
Future<ProbeCodecs> probeCodecs(String path) async {
  final player = Player(configuration: const PlayerConfiguration(vo: 'null', muted: true));
  try {
    final native = player.platform;
    if (native is! NativePlayer) return const ProbeCodecs(video: '', audio: '');
    await player.open(Media(Uri.file(path).toString()), play: false);
    try {
      await player.stream.tracks
          .firstWhere((tracks) => tracks.video.any((track) => track.id != 'auto' && track.id != 'no'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    final video = await native.getProperty('video-codec');
    final audio = await native.getProperty('audio-codec-name');
    return ProbeCodecs(video: video, audio: audio);
  } catch (error) {
    NetLog.instance.add('读取编码失败 $error');
    return const ProbeCodecs(video: '', audio: '');
  } finally {
    await player.dispose();
  }
}

/// Remux or transcode [input] to [output] with the libmpv that already plays video.
///
/// `copy` writes a new container header without re-encoding. HEVC in mp4 is
/// tagged `hvc1` so Photos will accept it. There is no second ffmpeg binary.
Future<void> remuxWithMpv({
  required String input,
  required String output,
  required String format,
  required bool copyVideo,
  required bool copyAudio,
  String? videoTag,
}) async {
  final player = Player(configuration: const PlayerConfiguration(vo: 'null', muted: true));
  final errors = <String>[];
  StreamSubscription<bool>? completedSub;
  StreamSubscription<String>? errorSub;
  try {
    final native = player.platform;
    if (native is! NativePlayer) {
      throw StateError('没有 mpv，不能封装');
    }
    await native.setProperty('o', output);
    await native.setProperty('of', format);
    await native.setProperty('ovc', copyVideo ? 'copy' : 'libx264');
    await native.setProperty('oac', copyAudio ? 'copy' : 'aac');
    if (!copyVideo) {
      await native.setProperty('ovcopts', 'preset=veryfast,crf=23');
    } else if (videoTag != null && videoTag.isNotEmpty) {
      await native.setProperty('ovcopts', 'vtag=$videoTag');
    }
    if (format == 'mp4') {
      try {
        await native.setProperty('ofopts', 'movflags=faststart');
      } catch (error) {
        NetLog.instance.add('mpv faststart 失败 $error');
      }
    }
    final done = Completer<void>();
    completedSub = player.stream.completed.listen((value) {
      if (value && !done.isCompleted) done.complete();
    });
    errorSub = player.stream.error.listen(errors.add);
    await player.open(Media(Uri.file(input).toString()));
    await player.play();
    await done.future.timeout(const Duration(minutes: 20));
    final file = File(output);
    if (!await file.exists() || await file.length() < 1024) {
      final detail = errors.isEmpty ? '封装结果是空的' : errors.join(' ');
      throw StateError(detail);
    }
  } finally {
    await completedSub?.cancel();
    await errorSub?.cancel();
    await player.dispose();
  }
}

/// Rewrite an MKV/WebM recording so the container header matches the packets.
///
/// stream-record muxes demuxed packets, and a clip that starts mid-file can
/// miss duration and cues. A copy remux writes a fresh header. The original
/// file is kept when the remux does not produce a readable file.
Future<String> finalizeRecordingContainer(String path) async {
  final extension = p.extension(path).replaceAll('.', '').toLowerCase();
  if (extension != 'mkv' && extension != 'webm') return path;
  final output = p.join(
    p.dirname(path),
    '.finalize-${DateTime.now().millisecondsSinceEpoch}.$extension',
  );
  try {
    await remuxWithMpv(
      input: path,
      output: output,
      format: extension == 'webm' ? 'webm' : 'matroska',
      copyVideo: true,
      copyAudio: true,
    );
    final probed = await probeCodecs(output);
    if (probed.video.isEmpty) {
      await File(output).delete();
      NetLog.instance.add('整理录制失败 新文件没有视频，保留原文件');
      return path;
    }
    final original = File(path);
    await original.delete();
    final dest = p.join(p.dirname(path), p.basename(path));
    await File(output).rename(dest);
    NetLog.instance.add('整理录制 $dest ${probed.video}');
    return dest;
  } catch (error) {
    final leftover = File(output);
    if (await leftover.exists()) await leftover.delete();
    NetLog.instance.add('整理录制失败 $error');
    return path;
  }
}

/// Copy, remux, or transcode [path] and save that file into the system gallery.
Future<String> saveRecordingToPhotos(String path) async {
  final granted = await Gal.hasAccess() || await Gal.requestAccess();
  if (!granted) {
    throw StateError('没有相册权限');
  }
  final codecs = await probeCodecs(path);
  final extension = p.extension(path);
  final plan = planPhotosSave(
    extension: extension,
    videoCodec: codecs.video,
    audioCodec: codecs.audio,
  );
  NetLog.instance.add('保存到相册 ${plan.kind.name} 视频=${codecs.video} 音频=${codecs.audio}');
  final String target;
  File? temporary;
  if (plan.kind == PhotosSaveKind.direct) {
    target = path;
  } else {
    temporary = File(p.join(Directory.systemTemp.path, 'emby-photo-${DateTime.now().millisecondsSinceEpoch}.mp4'));
    final hevc = hevcVideoCodec(codecs.video) && plan.kind != PhotosSaveKind.transcodeVideo;
    await remuxWithMpv(
      input: path,
      output: temporary.path,
      format: 'mp4',
      copyVideo: plan.kind != PhotosSaveKind.transcodeVideo,
      copyAudio: plan.kind == PhotosSaveKind.remux,
      videoTag: hevc ? 'hvc1' : null,
    );
    target = temporary.path;
  }
  try {
    await Gal.putVideo(target);
    NetLog.instance.add('已写入系统相册 ${p.basename(path)}');
    return plan.message;
  } finally {
    if (temporary != null && await temporary.exists()) {
      await temporary.delete();
    }
  }
}
