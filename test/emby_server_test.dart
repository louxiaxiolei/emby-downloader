import 'dart:convert';
import 'dart:io';

import 'package:emby_downloader/emby/net_log.dart';
import 'package:emby_downloader/emby/urls.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs only when [EMBY_IT_JSON] points at a file written by tool/emby_server_it.sh.
void main() {
  final jsonPath = Platform.environment['EMBY_IT_JSON'];
  test(
    'a separate mpv records a clip from a real Emby static stream and seeking returns',
    () async {
      final info = jsonDecode(File(jsonPath!).readAsStringSync()) as Map<String, dynamic>;
      final url = staticStreamUri(
        apiRoot: info['apiRoot'] as String,
        itemId: info['itemId'] as String,
        accessToken: info['accessToken'] as String,
        mediaSourceId: info['mediaSourceId'] as String,
        container: info['container'] as String?,
      ).toString();
      expect(NetLog.redact(Uri.parse(url)), isNot(contains('api_key=')));

      final work = Directory.systemTemp.createTempSync('emby-clip');
      addTearDown(() => work.deleteSync(recursive: true));
      final recorded = File('${work.path}/clip.mkv');

      final capture = await Process.run('mpv', [
        '--vo=null',
        '--ao=null',
        '--cache=yes',
        '--demuxer-max-bytes=8MiB',
        '--demuxer-readahead-secs=2',
        '--demuxer-max-back-bytes=8MiB',
        '--start=30',
        '--end=36',
        '--stream-record=${recorded.path}',
        url,
      ]);
      expect(capture.exitCode, 0, reason: '${capture.stdout}\n${capture.stderr}');
      expect(recorded.existsSync(), isTrue);
      expect(recorded.lengthSync(), greaterThan(1024));

      final probe = await Process.run('ffprobe', [
        '-v',
        'error',
        '-show_entries',
        'format=duration:stream=codec_name',
        '-of',
        'default=nw=1',
        recorded.path,
      ]);
      expect(probe.exitCode, 0, reason: probe.stderr.toString());
      final text = probe.stdout.toString();
      expect(text, contains('codec_name=h264'));
      expect(text, contains('codec_name=aac'));
      final duration = double.parse(
        RegExp(r'duration=([0-9.]+)').firstMatch(text)!.group(1)!,
      );
      // Started at 30s of a 40s file. The capture may read a little past
      // --end, but it must not be the whole file from 0:00.
      expect(duration, greaterThan(3));
      expect(duration, lessThan(20));

      final seek = await Process.run('mpv', [
        '--vo=null',
        '--ao=null',
        '--cache=yes',
        '--demuxer-max-bytes=64MiB',
        '--demuxer-max-back-bytes=32MiB',
        '--start=4',
        '--end=6',
        url,
      ]);
      expect(seek.exitCode, 0, reason: '${seek.stdout}\n${seek.stderr}');
    },
    skip: jsonPath == null ? 'set EMBY_IT_JSON to run against Emby Server' : false,
  );
}
