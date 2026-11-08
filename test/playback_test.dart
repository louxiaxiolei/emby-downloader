import 'package:emby_downloader/downloads/queue.dart';
import 'package:emby_downloader/downloads/speed.dart';
import 'package:emby_downloader/emby/models.dart';
import 'package:emby_downloader/emby/playback.dart';
import 'package:emby_downloader/emby/playback_guard.dart';
import 'package:emby_downloader/emby/urls.dart';
import 'package:emby_downloader/recordings/names.dart';
import 'package:emby_downloader/recordings/photos_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speed is bytes over the window, not a short burst blown up', () {
    final tracker = SpeedTracker();
    final start = DateTime.utc(2026, 1, 1);
    expect(
      tracker.addSample(at: start, bytes: 0, totalBytes: 5000000000),
      isNull,
    );
    // A 0.2s burst must not become the displayed rate.
    expect(
      tracker.addSample(
        at: start.add(const Duration(milliseconds: 200)),
        bytes: 20 * 1000000,
        totalBytes: 5000000000,
      ),
      isNull,
    );
    final estimate = tracker.addSample(
      at: start.add(const Duration(seconds: 5)),
      bytes: 60 * 1000000,
      totalBytes: 5000000000,
    );
    expect(estimate, isNotNull);
    expect(estimate!.bytesPerSecond, closeTo(12 * 1000000, 1000));
    expect(formatTransferSpeed(estimate.bytesPerSecond), '12.0 MB/s');
    expect(estimate.remaining!.inSeconds, closeTo((5000000000 - 60000000) / (12 * 1000000), 1));
    expect(formatClock(estimate.remaining!), '06:51');
  });

  test('progress label does not call the opening 0 a finished percent', () {
    expect(progressLabel(0), '准备中');
    expect(progressLabel(-1), '大小未知');
    expect(progressLabel(0.004), '<1%');
    expect(progressLabel(0.33), '33%');
    expect(progressBarValue(0), 0);
    expect(progressBarValue(-1), isNull);
    expect(progressBarValue(0.33), closeTo(0.33, 0.0001));
  });

  test('one task id is one queue row, and a saved or active item is not queued again', () {
    final live = <TrackedDownload>[];
    upsertDownload(
      live,
      TrackedDownload(taskId: 'a', itemId: 'totoro', kind: 'video', status: 'enqueued'),
    );
    upsertDownload(
      live,
      TrackedDownload(taskId: 'a', itemId: 'totoro', kind: 'video', status: 'running'),
    );
    expect(live, hasLength(1));
    expect(live.single.status, 'running');

    expect(
      itemAlreadyQueued(
        itemId: 'totoro',
        live: live,
        savedVideoItemIds: const [],
        inFlightItemIds: {},
      ),
      isTrue,
    );
    expect(
      itemAlreadyQueued(
        itemId: 'other',
        live: const [],
        savedVideoItemIds: const ['other'],
        inFlightItemIds: {},
      ),
      isTrue,
    );
    expect(
      itemAlreadyQueued(
        itemId: 'fresh',
        live: live,
        savedVideoItemIds: const [],
        inFlightItemIds: {'fresh'},
      ),
      isTrue,
    );
    expect(
      itemAlreadyQueued(
        itemId: 'fresh',
        live: live,
        savedVideoItemIds: const [],
        inFlightItemIds: {},
      ),
      isFalse,
    );
  });

  test('playback prefers the original file and falls back to HLS', () {
    final direct = resolvePlayback(
      base: 'http://192.168.1.10:8096',
      apiRoot: 'http://192.168.1.10:8096/emby',
      accessToken: 'token-1',
      itemId: 'movie-1',
      mediaSourceId: 'source-1',
      container: 'mkv',
      resume: const Duration(seconds: 90),
      playbackInfo: {
        'PlaySessionId': 'session-1',
        'MediaSources': [
          {
            'Id': 'source-1',
            'Container': 'mkv',
            'SupportsDirectPlay': true,
            'SupportsDirectStream': true,
            'SupportsTranscoding': true,
            'TranscodingUrl': '/emby/videos/movie-1/master.m3u8?PlaySessionId=session-1',
            'MediaStreams': [
              {'Index': 0, 'Type': 'Video', 'Codec': 'hevc'},
              {
                'Index': 2,
                'Type': 'Subtitle',
                'Language': 'chi',
                'DisplayTitle': '中文',
                'IsExternal': true,
                'IsTextSubtitleStream': true,
                'IsDefault': true,
              },
            ],
          },
        ],
      },
    );
    expect(direct.playMethod, 'DirectPlay');
    expect(direct.url, contains('/Videos/movie-1/stream.mkv'));
    expect(direct.url, contains('Static=true'));
    expect(direct.url, contains('api_key=token-1'));
    expect(direct.transcodeUrl, contains('master.m3u8'));
    expect(direct.playSessionId, 'session-1');
    expect(direct.subtitles.single.title, '中文');
    expect(direct.subtitles.single.url, contains('/Subtitles/2/Stream.srt'));
    expect(direct.resume, const Duration(seconds: 90));

    final transcode = resolvePlayback(
      base: 'http://192.168.1.10:8096',
      apiRoot: 'http://192.168.1.10:8096/emby',
      accessToken: 'token-1',
      itemId: 'movie-1',
      playbackInfo: {
        'PlaySessionId': 'session-2',
        'MediaSources': [
          {
            'Id': 'source-1',
            'SupportsDirectPlay': false,
            'SupportsDirectStream': false,
            'SupportsTranscoding': true,
            'TranscodingUrl': 'videos/movie-1/master.m3u8?PlaySessionId=session-2',
          },
        ],
      },
    );
    expect(transcode.playMethod, 'Transcode');
    expect(transcode.url, 'http://192.168.1.10:8096/emby/videos/movie-1/master.m3u8?PlaySessionId=session-2&api_key=token-1');
    expect(transcode.transcodeUrl, isNull);
  });

  test('item keeps the server resume point', () {
    final item = EmbyItem.fromJson({
      'Id': 'movie-1',
      'Name': '龙猫',
      'Type': 'Movie',
      'ProductionYear': 1988,
      'UserData': {'PlaybackPositionTicks': 900000000},
    });
    expect(resumePosition(item.playbackPositionTicks, item.runTimeTicks), const Duration(seconds: 90));
  });

  test('resume position skips the opening and the credits', () {
    expect(ticksFor(const Duration(seconds: 12)), 120000000);
    expect(resumePosition(120000000, null), const Duration(seconds: 12));
    expect(resumePosition(5 * 10000000, null), isNull);
    expect(resumePosition(105 * 10000000, 110 * 10000000), isNull);
  });

  test('episode posters use primary art, then the parent and the series', () {
    final episode = EmbyItem.fromJson({
      'Id': 'ep',
      'Name': '第一话',
      'Type': 'Episode',
      'SeriesId': 'series',
      'ImageTags': {'Primary': 'p1'},
      'ParentThumbItemId': 'season',
      'ParentThumbImageTag': 't1',
      'SeriesPrimaryImageTag': 's1',
    });
    final posters = artworkUrls(
      apiRoot: 'http://192.168.1.10:8096/emby',
      item: episode,
      wide: false,
      maxWidth: 400,
      accessToken: 'tok',
    );
    expect(posters.first, contains('/Items/ep/Images/Primary'));
    expect(posters.first, contains('tag=p1'));
    expect(posters.first, contains('api_key=tok'));
    expect(posters.first, isNot(contains('/Images/Thumb')));
    expect(
      posters.any((url) => url.contains('/Items/season/Images/Thumb') && url.contains('tag=t1')),
      isTrue,
    );
    expect(
      posters.any((url) => url.contains('/Items/series/Images/Primary') && url.contains('tag=s1')),
      isTrue,
    );
    expect(posters.any((url) => url.contains('/Items/ep/Images/Primary') && !url.contains('tag=')), isTrue);

    final series = EmbyItem.fromJson({
      'Id': 'series',
      'Name': '一拳超人',
      'Type': 'Series',
      'ImageTags': {'Primary': 'sp'},
    });
    final wide = artworkUrls(
      apiRoot: 'http://192.168.1.10:8096/emby',
      item: series,
      wide: true,
      accessToken: 'tok',
    );
    expect(wide.first, contains('/Items/series/Images/Primary'));
    expect(wide.first, contains('tag=sp'));
  });

  test('recording names keep the source container and a time range', () {
    expect(
      recordingFileName(
        title: '一拳超人',
        episode: 'S01E01',
        start: const Duration(minutes: 12, seconds: 34),
        end: const Duration(minutes: 13, seconds: 10),
        extension: 'mkv',
      ),
      '《一拳超人》S01E01_00-12-34_00-13-10.mkv',
    );
    expect(sourceContainer('http://host/Videos/1/stream.mp4?Static=true'), 'mp4');
    expect(sourceContainer('http://host/Videos/1/stream?Static=true'), 'mkv');
    expect(
      recordingTitle(EmbyItem(id: '1', name: '第一话', type: 'Episode', seriesName: '一拳超人', parentIndexNumber: 1, indexNumber: 1)),
      '一拳超人',
    );
  });

  test('a frame on screen is not a fatal playback error', () {
    expect(framesAreOnScreen(firstFrame: true, position: Duration.zero), isTrue);
    expect(framesAreOnScreen(firstFrame: false, position: const Duration(seconds: 2)), isTrue);
    expect(framesAreOnScreen(firstFrame: false, position: Duration.zero), isFalse);
    expect(surfacePlaybackError(framesVisible: true), isFalse);
    expect(surfacePlaybackError(framesVisible: false), isTrue);
    expect(hardPlaybackFailure('Failed to recognize file format.'), isTrue);
    expect(hardPlaybackFailure('HTTP error 404 Not Found'), isTrue);
    expect(hardPlaybackFailure('Can not open audio device.'), isFalse);
    expect(hardPlaybackFailure('Invalid audio PTS'), isFalse);
    expect(playbackHeaders({'Accept': 'application/json', 'X-Emby-Token': 't'})['Accept'], isNull);
  });

  test('direct play falls back to the server stream, then HLS', () {
    final direct = choosePlaybackFallback(
      currentUrl: 'http://host/Videos/1/stream?Static=true',
      triedDirect: false,
      triedTranscode: false,
      directUrl: 'http://host/Videos/1/stream.mkv?Static=true&PlaySessionId=s',
      directLabel: 'DirectPlay',
      transcodeUrl: 'http://host/emby/videos/1/master.m3u8',
    );
    expect(direct?.label, 'DirectPlay');
    expect(direct?.transcode, isFalse);

    final transcode = choosePlaybackFallback(
      currentUrl: 'http://host/Videos/1/stream.mkv?Static=true',
      triedDirect: true,
      triedTranscode: false,
      directUrl: 'http://host/Videos/1/stream.mkv?Static=true',
      transcodeUrl: 'http://host/emby/videos/1/master.m3u8',
    );
    expect(transcode?.label, '转码');
    expect(transcode?.transcode, isTrue);
    expect(
      choosePlaybackFallback(
        currentUrl: 'http://host/emby/videos/1/master.m3u8',
        triedDirect: true,
        triedTranscode: true,
        directUrl: 'http://host/Videos/1/stream.mkv',
        transcodeUrl: 'http://host/emby/videos/1/master.m3u8',
      ),
      isNull,
    );
  });

  test('instant playback keeps the container and device id off the json accept header', () {
    final playback = instantPlayback(
      apiRoot: 'http://192.168.1.10:8096/emby',
      accessToken: 'token-1',
      deviceId: 'phone-1',
      headers: playbackHeaders({'Accept': 'application/json', 'X-Emby-Token': 'token-1'}),
      item: EmbyItem(
        id: 'movie-1',
        name: '千与千寻',
        type: 'Movie',
        mediaSources: const [EmbyMediaSource(id: 'source-1', container: 'mkv')],
      ),
    );
    expect(playback.url, contains('/Videos/movie-1/stream.mkv'));
    expect(playback.url, contains('Static=true'));
    expect(playback.url, contains('MediaSourceId=source-1'));
    expect(playback.url, contains('DeviceId=phone-1'));
    expect(playback.url, contains('api_key=token-1'));
    expect(playback.playSessionId, isNull);
    expect(playback.headers.containsKey('Accept'), isFalse);
  });

  test('photos save remuxes mkv and transcodes only when the codec needs it', () {
    expect(
      planPhotosSave(extension: 'mp4', videoCodec: 'h264', audioCodec: 'aac').kind,
      PhotosSaveKind.direct,
    );
    expect(
      planPhotosSave(extension: 'mkv', videoCodec: 'hevc', audioCodec: 'aac').kind,
      PhotosSaveKind.remux,
    );
    expect(
      planPhotosSave(extension: 'mkv', videoCodec: 'h264', audioCodec: 'dts').kind,
      PhotosSaveKind.transcodeAudio,
    );
    expect(
      planPhotosSave(extension: 'mkv', videoCodec: 'av1', audioCodec: 'aac').kind,
      PhotosSaveKind.transcodeVideo,
    );
    expect(
      planPhotosSave(extension: 'mkv', videoCodec: '', audioCodec: '').kind,
      PhotosSaveKind.remux,
    );
  });

  test('device profile asks for the original and offers HLS', () {
    final profile = embyDirectPlayProfile();
    final direct = (profile['DirectPlayProfiles'] as List).single as Map;
    expect(direct['Container'], contains('mkv'));
    expect(direct['VideoCodec'], contains('hevc'));
    final transcode = (profile['TranscodingProfiles'] as List).single as Map;
    expect(transcode['Protocol'], 'hls');
  });
}
