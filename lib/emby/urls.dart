import 'models.dart';

const embyAppVersion = '1.0.0';
const embyDeviceName = 'Emby Downloader';

/// Parsed user input. [base] has no trailing slash and no `/emby` suffix.
class ServerInput {
  const ServerInput(this.base);

  final String base;
}

ServerInput parseServerInput(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    throw EmbyException('请填写服务器地址');
  }
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) {
    throw EmbyException('服务器地址无效');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw EmbyException('只支持 http 或 https');
  }
  var path = uri.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  const suffixes = ['/web/index.html', '/web'];
  for (final suffix in suffixes) {
    if (path.endsWith(suffix)) {
      path = path.substring(0, path.length - suffix.length);
      break;
    }
  }
  if (path.endsWith('/emby')) {
    path = path.substring(0, path.length - '/emby'.length);
  }
  if (path == '/') path = '';
  final origin = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString().replaceFirst(RegExp(r'/+$'), '');
  return ServerInput('$origin$path');
}

/// `X-Emby-Authorization` value.
///
/// Official schema (dev.emby.media, User Authentication):
/// `Emby UserId="...", Client="...", Device="...", DeviceId="...", Version="..."`.
/// UserId is omitted before login. The access token travels in `X-Emby-Token`,
/// not inside this header.
String embyAuthorizationHeader({
  required String client,
  required String deviceId,
  String? userId,
  String device = embyDeviceName,
  String version = embyAppVersion,
}) {
  final parts = <String>[
    if (userId != null && userId.isNotEmpty) 'UserId="${_headerValue(userId)}"',
    'Client="${_headerValue(client)}"',
    'Device="${_headerValue(device)}"',
    'DeviceId="${_headerValue(deviceId)}"',
    'Version="${_headerValue(version)}"',
  ];
  return 'Emby ${parts.join(', ')}';
}

String _headerValue(String value) =>
    value.replaceAll('"', '').replaceAll(RegExp(r'[\r\n]'), '').trim();

Uri apiUri(String apiRoot, String path, [Map<String, String>? query]) {
  final root = Uri.parse(apiRoot);
  final extra = path.split('/').where((segment) => segment.isNotEmpty);
  return root.replace(
    pathSegments: [
      ...root.pathSegments.where((segment) => segment.isNotEmpty),
      ...extra,
    ],
    queryParameters: query == null || query.isEmpty ? null : query,
  );
}

/// Original-file download. `GET /Items/{Id}/Download`.
///
/// `api_key` is the documented way for a native downloader to authenticate
/// after the app has been suspended. `MediaSourceId` selects a version.
Uri itemDownloadUri({
  required String apiRoot,
  required String itemId,
  required String accessToken,
  String? mediaSourceId,
}) {
  return apiUri(apiRoot, '/Items/$itemId/Download', {
    'api_key': accessToken,
    if (mediaSourceId != null && mediaSourceId.isNotEmpty)
      'MediaSourceId': mediaSourceId,
  });
}

/// Direct stream of the original file.
///
/// Documented as `/Videos/{Id}/stream.{Container}?Static=true`. Static=true
/// serves the source file without transcoding. Used when the download route
/// refuses the request (the user lacks the download role, or the route 404s).
Uri staticStreamUri({
  required String apiRoot,
  required String itemId,
  required String accessToken,
  required String mediaSourceId,
  String? container,
  String? playSessionId,
}) {
  final extension = cleanContainer(container);
  final file = extension == null ? 'stream' : 'stream.$extension';
  return apiUri(apiRoot, '/Videos/$itemId/$file', {
    'Static': 'true',
    if (mediaSourceId.isNotEmpty) 'MediaSourceId': mediaSourceId,
    'api_key': accessToken,
    if (playSessionId != null && playSessionId.isNotEmpty)
      'PlaySessionId': playSessionId,
  });
}

/// Second fallback. Older Emby builds expose `GET /Items/{Id}/File`.
Uri itemFileUri({
  required String apiRoot,
  required String itemId,
  required String accessToken,
}) {
  return apiUri(apiRoot, '/Items/$itemId/File', {'api_key': accessToken});
}

/// Text and external subtitle download.
///
/// Documented as `/Videos/{Id}/{MediaSourceId}/Subtitles/{Index}/Stream.{Format}`.
/// Text streams are requested as `.srt`. Image/binary external tracks keep
/// their codec extension.
Uri subtitleUri({
  required String apiRoot,
  required String itemId,
  required String mediaSourceId,
  required int index,
  required String format,
  required String accessToken,
}) {
  final safeFormat = cleanContainer(format) ?? 'srt';
  return apiUri(
    apiRoot,
    '/Videos/$itemId/$mediaSourceId/Subtitles/$index/Stream.$safeFormat',
    {'api_key': accessToken},
  );
}

Uri imageUri({
  required String apiRoot,
  required String itemId,
  required String type,
  String? tag,
  int? maxWidth,
  int? maxHeight,
  int? index,
}) {
  final segments = '/Items/$itemId/Images/$type${index == null ? '' : '/$index'}';
  return apiUri(apiRoot, segments, {
    'quality': '85',
    if (maxWidth != null) 'maxWidth': '$maxWidth',
    if (maxHeight != null) 'maxHeight': '$maxHeight',
    if (tag != null && tag.isNotEmpty) 'tag': tag,
  });
}

String? cleanContainer(String? container) {
  if (container == null) return null;
  final token = container.split(RegExp(r'[,;\s]')).first.trim().toLowerCase();
  if (RegExp(r'^[a-z0-9]{1,8}$').hasMatch(token)) return token;
  return null;
}

String sanitizeSegment(String input) {
  var text = input.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001F]'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  text = text.replaceAll(RegExp(r'^\.+'), '');
  if (text.isEmpty || text == '?') return '未命名';
  if (text.length > 60) text = text.substring(0, 60).trim();
  return text;
}

String sanitizeFileName(String input) {
  final text = sanitizeSegment(input);
  if (text == '未命名') return '未命名.bin';
  return text;
}

String? episodeCode(EmbyItem item) {
  if (item.parentIndexNumber == null && item.indexNumber == null) return null;
  final season = (item.parentIndexNumber ?? 0).toString().padLeft(2, '0');
  final episode = (item.indexNumber ?? 0).toString().padLeft(2, '0');
  return 'S$season' 'E$episode';
}

String mediaTitle(EmbyItem item) {
  final code = episodeCode(item);
  if (item.type == 'Episode') {
    final series = item.seriesName;
    if (series != null && series.isNotEmpty && code != null) {
      return '$series $code ${item.name}';
    }
  }
  if (item.type == 'Movie' && item.productionYear != null) {
    return '${item.name} (${item.productionYear})';
  }
  return item.name;
}

String mediaDirectory(EmbyItem item) {
  if (item.type == 'Episode') {
    final series = sanitizeSegment(item.seriesName ?? '剧集');
    final season = item.parentIndexNumber != null
        ? '第${item.parentIndexNumber}季'
        : sanitizeSegment(item.seasonName ?? '未知季');
    return 'Emby/$series/$season';
  }
  if (item.type == 'Movie') return 'Emby/电影';
  if (item.type == 'Audio' || item.type == 'AudioBook') return 'Emby/音频';
  return 'Emby/其他';
}

String videoFileName(EmbyItem item, EmbyMediaSource? source) {
  final path = source?.path ?? item.path;
  String name;
  if (path != null && path.trim().isNotEmpty) {
    name = path.split(RegExp(r'[\\/]')).last;
  } else {
    final extension = cleanContainer(source?.container);
    name = extension == null ? item.name : '${item.name}.$extension';
  }
  name = sanitizeFileName(name);
  final code = episodeCode(item);
  if (item.type == 'Episode' &&
      code != null &&
      !name.toLowerCase().contains(code.toLowerCase())) {
    final dot = name.lastIndexOf('.');
    if (dot > 0) {
      name = sanitizeFileName(
        '${name.substring(0, dot)} $code${name.substring(dot)}',
      );
    } else {
      name = sanitizeFileName('$name $code');
    }
  }
  return name;
}

String subtitleFileName(String videoName, EmbyStream stream, {bool withIndex = false}) {
  final dot = videoName.lastIndexOf('.');
  final base = dot > 0 ? videoName.substring(0, dot) : videoName;
  final language = sanitizeSegment(stream.language ?? 'und');
  final extension = stream.isTextSubtitleStream
      ? 'srt'
      : (cleanContainer(stream.codec) ?? 'sub');
  final index = withIndex ? '.${stream.index}' : '';
  return sanitizeFileName('$base.$language$index.$extension');
}

String uniqueFileName(String filename, Set<String> used) {
  if (used.add(filename)) return filename;
  final dot = filename.lastIndexOf('.');
  final base = dot > 0 ? filename.substring(0, dot) : filename;
  final extension = dot > 0 ? filename.substring(dot) : '';
  var index = 2;
  while (!used.add('$base ($index)$extension')) {
    index++;
  }
  return '$base ($index)$extension';
}

String collectionLabel(String? collectionType) {
  return switch (collectionType) {
    'movies' => '电影',
    'tvshows' => '剧集',
    'music' => '音乐',
    'homevideos' => '家庭视频',
    'musicvideos' => '音乐视频',
    'books' => '图书',
    'boxsets' => '合集',
    'playlists' => '播放列表',
    'photos' => '照片',
    'livetv' => '电视直播',
    'channels' => '频道',
    _ => '资料库',
  };
}

String formatRuntime(int? ticks) {
  if (ticks == null || ticks <= 0) return '';
  final seconds = ticks ~/ 10000000;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0 && minutes > 0) return '$hours小时$minutes分钟';
  if (hours > 0) return '$hours小时';
  if (minutes > 0) return '$minutes分钟';
  return '$seconds秒';
}

String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final digits = value >= 10 || index == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[index]}';
}

String timeAgo(DateTime? time) {
  if (time == null) return '';
  final delta = DateTime.now().difference(time.toLocal());
  if (delta.isNegative || delta.inSeconds < 45) return '刚刚';
  if (delta.inMinutes < 60) return '${delta.inMinutes}分钟前';
  if (delta.inHours < 24) return '${delta.inHours}小时前';
  if (delta.inDays < 14) return '${delta.inDays}天前';
  return formatWhen(time.toIso8601String());
}

String formatSeen(int? ticks) {
  if (ticks == null || ticks <= 0) return '';
  final total = ticks ~/ 10000000;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) return '看到 $hours:${two(minutes)}:${two(seconds)}';
  return '看到 ${two(minutes)}:${two(seconds)}';
}

String formatWhen(String iso) {
  final time = DateTime.tryParse(iso)?.toLocal();
  if (time == null) return '';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}

String? videoSummary(EmbyMediaSource? source) {
  if (source == null) return null;
  final video = source.streams.where((stream) => stream.type == 'Video');
  if (video.isEmpty) return source.name;
  final stream = video.first;
  final parts = <String>[
    if (stream.width != null && stream.height != null)
      '${stream.width}×${stream.height}',
    if (cleanContainer(stream.codec) != null) stream.codec!.toUpperCase(),
    if (source.name != null && source.name!.isNotEmpty) source.name!,
  ];
  return parts.join(' · ');
}

String mimeForFilename(String filename) {
  final lower = filename.toLowerCase();
  final dot = lower.lastIndexOf('.');
  final extension = dot >= 0 ? lower.substring(dot) : '';
  return switch (extension) {
    '.mp4' || '.m4v' => 'video/mp4',
    '.mkv' => 'video/x-matroska',
    '.avi' => 'video/x-msvideo',
    '.webm' => 'video/webm',
    '.mov' => 'video/quicktime',
    '.ts' || '.m2ts' => 'video/mp2t',
    '.wmv' => 'video/x-ms-wmv',
    '.mpg' || '.mpeg' => 'video/mpeg',
    '.srt' => 'application/x-subrip',
    '.vtt' => 'text/vtt',
    '.ass' || '.ssa' => 'text/x-ssa',
    '.mp3' => 'audio/mpeg',
    '.flac' => 'audio/flac',
    '.m4a' || '.aac' => 'audio/mp4',
    _ => 'application/octet-stream',
  };
}
