import 'dart:io';

import 'package:emby_downloader/recordings/clip_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Exercises the same libmpv capture the app uses, not the mpv CLI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captureStreamRange writes a mid-file clip with video', () async {
    if (!await _hasTool('ffmpeg') || !await _hasTool('ffprobe')) {
      markTestSkipped('ffmpeg is not installed');
      return;
    }
    try {
      MediaKit.ensureInitialized();
    } catch (error) {
      markTestSkipped('libmpv is not installed: $error');
      return;
    }
    final work = Directory.systemTemp.createTempSync('clip-capture');
    addTearDown(() => work.deleteSync(recursive: true));
    final source = File('${work.path}/source.mkv');
    final made = await Process.run('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'testsrc=size=160x120:rate=25',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=48000',
      '-t',
      '40',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-shortest',
      source.path,
    ]);
    expect(made.exitCode, 0, reason: '${made.stdout}\n${made.stderr}');

    final output = '${work.path}/clip.mkv';
    final bytes = await captureStreamRange(
      url: source.uri.toString(),
      output: output,
      headers: const {},
      start: const Duration(seconds: 30),
      end: const Duration(seconds: 36),
      onProgress: (_) {},
    );
    expect(bytes, greaterThan(1024));

    final probe = await Process.run('ffprobe', [
      '-v',
      'error',
      '-show_entries',
      'format=duration:stream=codec_name',
      '-of',
      'default=nw=1',
      output,
    ]);
    expect(probe.exitCode, 0, reason: probe.stderr.toString());
    final text = probe.stdout.toString();
    expect(text, contains('codec_name=h264'));
    expect(text, contains('codec_name=aac'));
    final duration = double.parse(RegExp(r'duration=([0-9.]+)').firstMatch(text)!.group(1)!);
    expect(duration, greaterThan(3));
    expect(duration, lessThan(20));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<bool> _hasTool(String name) async {
  try {
    final result = await Process.run('which', [name]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
