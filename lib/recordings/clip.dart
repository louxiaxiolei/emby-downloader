import '../emby/playback.dart';

/// Decimal seconds for mpv `dump-cache` and `start`/`end`.
String mpvSeconds(Duration position) {
  final millis = position.inMilliseconds < 0 ? 0 : position.inMilliseconds;
  return (millis / 1000).toStringAsFixed(3);
}

/// A dump range shorter than this is not worth a file.
const minRecordedSpan = Duration(milliseconds: 400);

bool recordSpanIsUsable(Duration start, Duration end) {
  return end - start >= minRecordedSpan;
}

/// Progressive Emby clip. `Static=true` is removed so the server can start
/// at [start] instead of sending the whole original file.
///
/// Wide codec lists let Emby remux (copy) when the source already matches,
/// and fall back to H.264/AAC when it does not.
String? embyClipUrl(String playbackUrl, Duration start) {
  final uri = Uri.tryParse(playbackUrl);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (!uri.path.toLowerCase().contains('/videos/')) return null;
  final segments = uri.pathSegments.toList();
  if (segments.isEmpty) return null;
  final last = segments.last.toLowerCase();
  if (!last.startsWith('stream')) return null;
  segments[segments.length - 1] = 'stream.mp4';
  final params = Map<String, String>.from(uri.queryParameters);
  params.removeWhere((key, _) => key.toLowerCase() == 'static');
  params['StartTimeTicks'] = '${ticksFor(start)}';
  params['VideoCodec'] = 'hevc,h264,vp9,av1,mpeg4';
  params['AudioCodec'] = 'aac,mp3,ac3,eac3,opus,flac';
  params['MaxStreamingBitrate'] = '140000000';
  params['CopyTimestamps'] = 'true';
  return uri.replace(pathSegments: segments, queryParameters: params).toString();
}
