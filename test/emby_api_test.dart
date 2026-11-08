import 'dart:convert';

import 'package:emby_downloader/emby/api.dart';
import 'package:emby_downloader/emby/models.dart';
import 'package:emby_downloader/emby/plan.dart';
import 'package:emby_downloader/emby/urls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parseServerInput normalizes home-server addresses', () {
    expect(parseServerInput('192.168.1.10:8096').base, 'http://192.168.1.10:8096');
    expect(parseServerInput('http://192.168.1.10:8096/').base, 'http://192.168.1.10:8096');
    expect(
      parseServerInput('http://192.168.1.10:8096/web/index.html').base,
      'http://192.168.1.10:8096',
    );
    expect(parseServerInput('http://192.168.1.10:8096/emby').base, 'http://192.168.1.10:8096');
    expect(parseServerInput('https://example.com/apps/emby/web').base, 'https://example.com/apps');
    expect(() => parseServerInput('ftp://example.com'), throwsA(isA<EmbyException>()));
  });

  test('authorization header matches the documented Emby schema', () {
    final beforeLogin = embyAuthorizationHeader(
      client: 'Android',
      deviceId: 'device-1',
    );
    expect(
      beforeLogin,
      'Emby Client="Android", Device="Emby Downloader", DeviceId="device-1", Version="1.0.0"',
    );
    expect(beforeLogin.contains('UserId'), isFalse);

    final afterLogin = embyAuthorizationHeader(
      client: 'iOS',
      deviceId: 'device-1',
      userId: 'user-1',
    );
    expect(afterLogin.startsWith('Emby UserId="user-1", Client="iOS"'), isTrue);
  });

  test('authenticate posts Pw and the X-Emby-Authorization header', () async {
    http.Request? login;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/System/Info/Public')) {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({'ServerName': '客厅', 'Id': 'server-1', 'Version': '4.8.11.0'}),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      login = request;
      return http.Response(
        jsonEncode({
          'AccessToken': 'token-1',
          'ServerId': 'server-1',
          'User': {'Name': 'me', 'Id': 'user-1'},
        }),
        200,
      );
    });

    final session = await authenticate(
      rawUrl: 'http://192.168.1.10:8096/web/index.html',
      username: 'me',
      password: 'secret',
      deviceId: 'device-1',
      clientName: 'Android',
      allowBadCertificate: false,
      httpClient: client,
    );

    expect(login, isNotNull);
    expect(login!.url.path, '/emby/Users/AuthenticateByName');
    expect(login!.headers['content-type'], contains('application/json'));
    expect(login!.headers['x-emby-authorization'], contains('Client="Android"'));
    expect(login!.headers['x-emby-authorization'], isNot(contains('UserId')));
    expect(jsonDecode(login!.body), {'Username': 'me', 'Pw': 'secret'});
    expect(session.apiRoot, 'http://192.168.1.10:8096/emby');
    expect(session.accessToken, 'token-1');
    expect(session.userId, 'user-1');
    expect(session.serverName, '客厅');
  });

  test('wrong password surfaces a Chinese error', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/System/Info/Public')) {
        return http.Response(jsonEncode({'ServerName': 'Emby', 'Id': 's'}), 200);
      }
      return http.Response('{}', 401);
    });
    expect(
      () => authenticate(
        rawUrl: 'http://host:8096',
        username: 'me',
        password: 'nope',
        deviceId: 'device',
        clientName: 'Android',
        allowBadCertificate: false,
        httpClient: client,
      ),
      throwsA(
        isA<EmbyException>().having((error) => error.message, 'message', '用户名或密码不正确'),
      ),
    );
  });

  test('download plan uses the item download route, then static and file fallbacks', () {
    final item = EmbyItem.fromJson({
      'Id': 'movie-1',
      'Name': '示例',
      'Type': 'Movie',
      'ProductionYear': 2024,
      'Path': '/media/示例 (2024).mkv',
      'MediaSources': [
        {
          'Id': 'source-1',
          'Path': '/media/示例 (2024).mkv',
          'Container': 'mkv',
          'Size': 1073741824,
          'MediaStreams': [
            {'Index': 0, 'Type': 'Video', 'Codec': 'hevc', 'Width': 1920, 'Height': 1080},
            {
              'Index': 2,
              'Type': 'Subtitle',
              'Codec': 'subrip',
              'Language': 'chi',
              'DisplayTitle': '中文',
              'IsExternal': true,
              'IsTextSubtitleStream': true,
            },
            {
              'Index': 3,
              'Type': 'Subtitle',
              'Codec': 'subrip',
              'Language': 'eng',
              'IsExternal': false,
              'IsTextSubtitleStream': true,
            },
          ],
        },
      ],
    });

    final plans = planItemDownload(
      apiRoot: 'http://192.168.1.10:8096/emby',
      accessToken: 'token-1',
      item: item,
      source: item.mediaSources.single,
    );

    expect(plans, hasLength(2));
    expect(plans.first.kind, 'video');
    expect(plans.first.filename, '示例 (2024).mkv');
    expect(plans.first.urls[0], contains('/emby/Items/movie-1/Download'));
    expect(plans.first.urls[0], contains('api_key=token-1'));
    expect(plans.first.urls[0], contains('MediaSourceId=source-1'));
    expect(plans.first.urls[1], contains('/emby/Videos/movie-1/stream.mkv'));
    expect(plans.first.urls[1], contains('Static=true'));
    expect(plans.first.urls[2], contains('/emby/Items/movie-1/File'));
    expect(plans.last.kind, 'subtitle');
    expect(plans.last.filename, '示例 (2024).chi.srt');
    expect(
      plans.last.urls.single,
      contains('/emby/Videos/movie-1/source-1/Subtitles/2/Stream.srt'),
    );
    final meta = DownloadMeta(
      kind: 'video',
      itemId: item.id,
      title: '示例 "特别版"',
      stage: 1,
      urls: plans.first.urls,
    );
    expect(DownloadMeta.decode(meta.encode()).title, '示例 "特别版"');
    expect(DownloadMeta.decode(meta.encode()).stage, 1);
  });

  test('virtual episodes and embedded-only subtitles are not extra downloads', () {
    final virtual = EmbyItem.fromJson({
      'Id': 'ep',
      'Name': '未播出',
      'Type': 'Episode',
      'LocationType': 'Virtual',
    });
    expect(virtual.canDownload, isFalse);

    final episode = EmbyItem.fromJson({
      'Id': 'ep-2',
      'Name': '开端',
      'Type': 'Episode',
      'SeriesName': '示例剧',
      'ParentIndexNumber': 1,
      'IndexNumber': 2,
      'Path': r'C:\media\episode.mkv',
    });
    expect(episodeCode(episode), 'S01E02');
    expect(videoFileName(episode, null), contains('S01E02'));
    expect(mediaDirectory(episode), 'Emby/示例剧/第1季');
  });

  test('library payload parses views and keeps external subtitles', () {
    final page = EmbyPage.fromJson({
      'TotalRecordCount': 1,
      'Items': [
        {
          'Name': '电影',
          'Id': 'lib',
          'Type': 'CollectionFolder',
          'CollectionType': 'movies',
          'ImageTags': {'Primary': 'tag'},
        },
      ],
    });
    expect(page.items.single.collectionType, 'movies');
    expect(collectionLabel('movies'), '电影');
    expect(formatBytes(1073741824), '1.0 GB');
    expect(formatRuntime(54000000000), '1小时30分钟');
  });
}
