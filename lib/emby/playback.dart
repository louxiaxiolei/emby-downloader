import 'models.dart';
import 'urls.dart';

/// Emby ticks are 100 ns. Ten ticks are one microsecond.
int ticksFor(Duration position) => position.inMicroseconds * 10;

/// Resume when Emby has a position past 10 seconds and not in the last 5%.
Duration? resumePosition(int? ticks, int? runtimeTicks) {
  if (ticks == null || ticks < 10 * 10000000) return null;
  if (runtimeTicks != null && runtimeTicks > 0 && ticks >= runtimeTicks * 0.95) return null;
  return Duration(microseconds: ticks ~/ 10);
}

/// Device profile that asks Emby for the original file, with HLS as a fallback.
Map<String, dynamic> embyDirectPlayProfile() {
  const videoContainers = 'mkv,mp4,m4v,mov,avi,ts,m2ts,webm,wmv,mpg,mpeg';
  const videoCodecs = 'h264,hevc,h265,mpeg4,vp8,vp9,av1,mpeg2video';
  const audioCodecs = 'aac,mp3,ac3,eac3,dts,truehd,flac,opus,vorbis,pcm,mp2,alac';
  return {
    'MaxStreamingBitrate': 140000000,
    'MaxStaticBitrate': 140000000,
    'MusicStreamingTranscodingBitrate': 192000,
    'DirectPlayProfiles': [
      {
        'Container': videoContainers,
        'Type': 'Video',
        'VideoCodec': videoCodecs,
        'AudioCodec': audioCodecs,
      },
    ],
    'TranscodingProfiles': [
      {
        'Container': 'ts',
        'Type': 'Video',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'MaxAudioChannels': '6',
      },
    ],
    'SubtitleProfiles': [
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'ssa', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'subrip', 'Method': 'Embed'},
      {'Format': 'ass', 'Method': 'Embed'},
      {'Format': 'ssa', 'Method': 'Embed'},
      {'Format': 'pgs', 'Method': 'Embed'},
      {'Format': 'pgssub', 'Method': 'Embed'},
    ],
  };
}

class PlaybackSubtitle {
  const PlaybackSubtitle({
    required this.title,
    this.url,
    this.language,
    this.isDefault = false,
  });

  final String title;
  final String? url;
  final String? language;
  final bool isDefault;
}

class ResolvedPlayback {
  const ResolvedPlayback({
    required this.url,
    required this.playMethod,
    required this.headers,
    this.transcodeUrl,
    this.playSessionId,
    this.mediaSourceId,
    this.subtitles = const [],
    this.resume,
  });

  /// Direct play / direct stream of the original when Emby allows it.
  final String url;

  /// HLS master playlist used only when the original cannot be played.
  final String? transcodeUrl;

  /// `DirectPlay`, `DirectStream`, or `Transcode`.
  final String playMethod;
  final String? playSessionId;
  final String? mediaSourceId;
  final Map<String, String> headers;
  final List<PlaybackSubtitle> subtitles;
  final Duration? resume;

  bool get reportsToServer => playSessionId != null && playSessionId!.isNotEmpty;
}

String resolveEmbyReference({
  required String base,
  required String apiRoot,
  required String raw,
}) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
  final originUri = Uri.parse(base);
  final origin = Uri(
    scheme: originUri.scheme,
    host: originUri.host,
    port: originUri.hasPort ? originUri.port : null,
  ).toString();
  if (trimmed.startsWith('/')) {
    final prefix = originUri.path;
    if (prefix.isNotEmpty && prefix != '/' && !trimmed.startsWith(prefix)) {
      return '$origin$prefix$trimmed';
    }
    return '$origin$trimmed';
  }
  final root = apiRoot.endsWith('/') ? apiRoot.substring(0, apiRoot.length - 1) : apiRoot;
  return '$root/$trimmed';
}

String withApiKey(String url, String accessToken) {
  final uri = Uri.parse(url);
  if ((uri.queryParameters['api_key'] ?? '').isNotEmpty) return url;
  return uri.replace(
    queryParameters: {...uri.queryParameters, 'api_key': accessToken},
  ).toString();
}

/// Opens the original file immediately. PlaybackInfo is not required to start.
ResolvedPlayback instantPlayback({
  required String apiRoot,
  required String accessToken,
  required EmbyItem item,
  Map<String, String> headers = const {},
  String? deviceId,
}) {
  final source = item.mediaSources.isEmpty ? null : item.mediaSources.first;
  final sourceId = source != null && source.id.isNotEmpty ? source.id : '';
  final url = withApiKey(
    staticStreamUri(
      apiRoot: apiRoot,
      itemId: item.id,
      accessToken: accessToken,
      mediaSourceId: sourceId,
      container: source?.container,
      deviceId: deviceId,
    ).toString(),
    accessToken,
  );
  return ResolvedPlayback(
    url: url,
    playMethod: 'DirectPlay',
    headers: headers,
    mediaSourceId: sourceId.isEmpty ? null : sourceId,
    resume: resumePosition(item.playbackPositionTicks, item.runTimeTicks),
  );
}

/// Picks an original-file URL when PlaybackInfo allows it, otherwise HLS.
ResolvedPlayback resolvePlayback({
  required String base,
  required String apiRoot,
  required String accessToken,
  required String itemId,
  String? mediaSourceId,
  String? container,
  Map<String, dynamic>? playbackInfo,
  List<EmbyStream> knownStreams = const [],
  Duration? resume,
  Map<String, String> headers = const {},
}) {
  final chosen = _source(playbackInfo, mediaSourceId);
  final sourceId = (chosen?['Id'] as String?)?.trim().isNotEmpty == true
      ? chosen!['Id'] as String
      : (mediaSourceId ?? itemId);
  final sessionId = playbackInfo?['PlaySessionId']?.toString();
  final streams = _streams(chosen) ?? knownStreams;
  final directPlay = chosen?['SupportsDirectPlay'] as bool? ?? true;
  final directStream = chosen?['SupportsDirectStream'] as bool? ?? directPlay;
  final original = withApiKey(
    staticStreamUri(
      apiRoot: apiRoot,
      itemId: itemId,
      accessToken: accessToken,
      mediaSourceId: sourceId,
      container: (chosen?['Container'] as String?) ?? container,
      playSessionId: sessionId,
    ).toString(),
    accessToken,
  );
  final directStreamUrl = _reference(base, apiRoot, chosen?['DirectStreamUrl']?.toString());
  final transcodeUrl = _reference(base, apiRoot, chosen?['TranscodingUrl']?.toString());
  final transcode = transcodeUrl == null ? null : withApiKey(transcodeUrl, accessToken);
  final canOriginal = chosen == null || directPlay || directStream;
  final String url;
  final String method;
  if (canOriginal && directPlay) {
    url = original;
    method = 'DirectPlay';
  } else if (canOriginal && (directStreamUrl != null || directStream)) {
    url = directStreamUrl == null ? original : withApiKey(directStreamUrl, accessToken);
    method = 'DirectStream';
  } else if (transcode != null) {
    url = transcode;
    method = 'Transcode';
  } else {
    url = original;
    method = 'DirectPlay';
  }
  return ResolvedPlayback(
    url: url,
    transcodeUrl: method == 'Transcode' ? null : transcode,
    playMethod: method,
    playSessionId: sessionId == null || sessionId.isEmpty ? 'play-$itemId' : sessionId,
    mediaSourceId: sourceId,
    headers: headers,
    subtitles: _subtitles(
      base: base,
      apiRoot: apiRoot,
      accessToken: accessToken,
      itemId: itemId,
      mediaSourceId: sourceId,
      streams: streams,
    ),
    resume: resume,
  );
}

Map<String, dynamic>? _source(Map<String, dynamic>? info, String? mediaSourceId) {
  final raw = info?['MediaSources'];
  if (raw is! List) return null;
  Map<String, dynamic>? first;
  for (final entry in raw) {
    if (entry is! Map) continue;
    final source = Map<String, dynamic>.from(entry);
    first ??= source;
    if (mediaSourceId != null && source['Id'] == mediaSourceId) return source;
  }
  return first;
}

List<EmbyStream>? _streams(Map<String, dynamic>? source) {
  final raw = source?['MediaStreams'];
  if (raw is! List) return null;
  return [
    for (final entry in raw)
      if (entry is Map) EmbyStream.fromJson(Map<String, dynamic>.from(entry)),
  ];
}

String? _reference(String base, String apiRoot, String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return resolveEmbyReference(base: base, apiRoot: apiRoot, raw: raw);
}

List<PlaybackSubtitle> _subtitles({
  required String base,
  required String apiRoot,
  required String accessToken,
  required String itemId,
  required String mediaSourceId,
  required List<EmbyStream> streams,
}) {
  final result = <PlaybackSubtitle>[];
  for (final stream in streams) {
    if (stream.type != 'Subtitle' || !stream.isExternal) continue;
    final delivered = stream.deliveryUrl;
    final raw = delivered != null && delivered.isNotEmpty
        ? resolveEmbyReference(base: base, apiRoot: apiRoot, raw: delivered)
        : subtitleUri(
            apiRoot: apiRoot,
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            index: stream.index,
            format: stream.isTextSubtitleStream ? 'srt' : (stream.codec ?? 'sub'),
            accessToken: accessToken,
          ).toString();
    result.add(
      PlaybackSubtitle(
        title: stream.displayTitle ?? stream.language ?? '外挂字幕',
        url: withApiKey(raw, accessToken),
        language: stream.language,
        isDefault: stream.isDefault,
      ),
    );
  }
  return result;
}
