import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'models.dart';
import 'urls.dart';

http.Client createHttpClient({required bool allowBadCertificate}) {
  final io = HttpClient();
  io.connectionTimeout = const Duration(seconds: 15);
  if (allowBadCertificate) {
    io.badCertificateCallback = (certificate, host, port) => true;
  }
  return IOClient(io);
}

class EmbyClient {
  EmbyClient({
    required this.session,
    required this.deviceId,
    required this.clientName,
    required http.Client httpClient,
    this.ownsClient = false,
  }) : _http = httpClient;

  final EmbySession session;
  final String deviceId;
  final String clientName;
  final bool ownsClient;
  final http.Client _http;

  Map<String, String> get headers => {
    'Accept': 'application/json',
    'X-Emby-Authorization': embyAuthorizationHeader(
      client: clientName,
      deviceId: deviceId,
      userId: session.userId,
    ),
    'X-Emby-Token': session.accessToken,
  };

  Future<EmbyPage> views() {
    return _getPage('/Users/${session.userId}/Views');
  }

  Future<EmbyPage> children({
    required String parentId,
    required int start,
    int limit = 60,
  }) {
    return _getPage('/Users/${session.userId}/Items', {
      'ParentId': parentId,
      'StartIndex': '$start',
      'Limit': '$limit',
      'SortBy': 'SortName',
      'SortOrder': 'Ascending',
      'Fields':
          'PrimaryImageAspectRatio,Overview,ProductionYear,ChildCount,OfficialRating,CommunityRating,ParentIndexNumber,IndexNumber,SeriesName,SeasonName,Path',
    });
  }

  Future<EmbyItem> item(String id) async {
    final json = await _getObject('/Users/${session.userId}/Items/$id', {
      'Fields':
          'Overview,Genres,People,MediaSources,MediaStreams,Path,Studios,OfficialRating,CommunityRating,RunTimeTicks,ProductionYear,PremiereDate,ChildCount,IndexNumber,ParentIndexNumber,SeriesName,SeasonName,OriginalTitle',
    });
    return EmbyItem.fromJson(json);
  }

  Future<EmbyPage> seasons(String seriesId) {
    return _getPage('/Shows/$seriesId/Seasons', {
      'UserId': session.userId,
      'Fields': 'Overview,PrimaryImageAspectRatio,ChildCount,PremiereDate',
    });
  }

  Future<EmbyPage> episodes({
    required String seriesId,
    required String seasonId,
  }) {
    return _getPage('/Shows/$seriesId/Episodes', {
      'UserId': session.userId,
      'SeasonId': seasonId,
      'Fields':
          'Overview,MediaSources,MediaStreams,Path,IndexNumber,ParentIndexNumber,SeriesName,SeasonName,RunTimeTicks,CommunityRating',
    });
  }

  Future<EmbyPage> search(String term) {
    return _getPage('/Users/${session.userId}/Items', {
      'SearchTerm': term,
      'Recursive': 'true',
      'IncludeItemTypes': 'Movie,Series,Episode,Video',
      'Limit': '40',
      'Fields':
          'Overview,ProductionYear,PrimaryImageAspectRatio,IndexNumber,ParentIndexNumber,SeriesName,SeasonName',
    });
  }

  Future<void> logout() async {
    final response = await _http
        .post(
          apiUri(session.apiRoot, '/Sessions/Logout'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) return;
    if (response.statusCode >= 400) {
      throw EmbyException('退出登录失败（${response.statusCode}）', statusCode: response.statusCode);
    }
  }

  String imageUrl(
    EmbyItem item, {
    String type = 'Primary',
    int? maxWidth,
    int? maxHeight,
  }) {
    final tag = type == 'Backdrop' ? item.backdropTag : item.primaryTag;
    if (type == 'Primary' && tag == null) return '';
    if (type == 'Backdrop' && tag == null) return '';
    return imageUri(
      apiRoot: session.apiRoot,
      itemId: item.id,
      type: type,
      tag: tag,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      index: type == 'Backdrop' ? 0 : null,
    ).toString();
  }

  void close() {
    if (ownsClient) _http.close();
  }

  Future<EmbyPage> _getPage(String path, [Map<String, String>? query]) async {
    final json = await _getObject(path, query);
    return EmbyPage.fromJson(json);
  }

  Future<Map<String, dynamic>> _getObject(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await _http
        .get(apiUri(session.apiRoot, path, query), headers: headers)
        .timeout(const Duration(seconds: 25));
    return _decodeObject(response);
  }
}

Future<EmbySession> authenticate({
  required String rawUrl,
  required String username,
  required String password,
  required String deviceId,
  required String clientName,
  required bool allowBadCertificate,
  http.Client? httpClient,
}) async {
  final input = parseServerInput(rawUrl);
  final client = httpClient ?? createHttpClient(allowBadCertificate: allowBadCertificate);
  final closeClient = httpClient == null;
  try {
    final probed = await _probe(client, input.base);
    final header = embyAuthorizationHeader(
      client: clientName,
      deviceId: deviceId,
    );
    final response = await client
        .post(
          apiUri(probed.apiRootFor(input.base), '/Users/AuthenticateByName'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'X-Emby-Authorization': header,
          },
          body: jsonEncode({'Username': username, 'Pw': password}),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw EmbyException('用户名或密码不正确', statusCode: response.statusCode);
    }
    final json = _decodeObject(response);
    final user = json['User'];
    final token = json['AccessToken'] as String?;
    final userId = user is Map ? user['Id'] as String? : null;
    final name = user is Map ? user['Name'] as String? : username;
    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      throw EmbyException('服务器没有返回访问令牌');
    }
    return EmbySession(
      base: input.base,
      apiPrefix: probed.apiPrefix,
      serverName: probed.serverName,
      serverId: (json['ServerId'] as String?) ?? probed.serverId,
      serverVersion: probed.serverVersion,
      userId: userId,
      username: name ?? username,
      accessToken: token,
      allowBadCertificate: allowBadCertificate,
    );
  } finally {
    if (closeClient) client.close();
  }
}

class _Probe {
  const _Probe({
    required this.apiPrefix,
    required this.serverName,
    required this.serverId,
    required this.serverVersion,
  });

  final String apiPrefix;
  final String serverName;
  final String serverId;
  final String serverVersion;

  String apiRootFor(String base) => '$base$apiPrefix';
}

Future<_Probe> _probe(http.Client client, String base) async {
  Object? lastError;
  for (final prefix in const ['/emby', '']) {
    try {
      final response = await client
          .get(
            apiUri('$base$prefix', '/System/Info/Public'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) continue;
      final json = jsonDecode(response.body);
      if (json is Map && (json['ServerName'] != null || json['Id'] != null)) {
        return _Probe(
          apiPrefix: prefix,
          serverName: json['ServerName']?.toString() ?? 'Emby',
          serverId: json['Id']?.toString() ?? '',
          serverVersion: json['Version']?.toString() ?? '',
        );
      }
    } catch (error) {
      lastError = error;
    }
  }
  if (lastError is HandshakeException) {
    throw EmbyException('TLS 证书不被信任。可以打开“信任自签名证书”，或改用 http 地址');
  }
  if (lastError is SocketException || lastError is TimeoutException) {
    throw EmbyException('连不上服务器。请检查地址、端口，以及手机和服务器是否在同一网络');
  }
  throw EmbyException('这不是可用的 Emby 服务。地址示例：http://192.168.1.10:8096');
}

Map<String, dynamic> _decodeObject(http.Response response) {
  if (response.statusCode == 401) throw EmbyUnauthorized();
  if (response.statusCode >= 400) {
    throw EmbyException(
      _serverMessage(response) ?? '服务器返回 ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }
  final json = jsonDecode(response.body);
  if (json is Map<String, dynamic>) return json;
  if (json is Map) return Map<String, dynamic>.from(json);
  throw EmbyException('服务器返回了无法识别的内容');
}

String? _serverMessage(http.Response response) {
  try {
    final json = jsonDecode(response.body);
    if (json is Map) {
      final message = json['Message'] ?? json['ErrorMessage'];
      if (message is String && message.isNotEmpty) return message;
    }
  } catch (_) {}
  return null;
}

String friendlyError(Object error) {
  if (error is EmbyException) return error.message;
  if (error is TimeoutException) return '连接超时';
  if (error is SocketException) return '无法连接到服务器';
  if (error is HandshakeException) {
    return 'TLS 握手失败。如果是自签名证书，请打开“信任自签名证书”，或改用 http';
  }
  return '请求失败';
}
