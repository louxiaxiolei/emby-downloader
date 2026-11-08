// Decisions the player can unit-test without opening mpv.

/// A frame is on screen, so a later mpv log must not become a fatal overlay.
bool framesAreOnScreen({required bool firstFrame, required Duration position}) {
  return firstFrame || position > const Duration(milliseconds: 400);
}

/// Fatal UI is only for an attempt that never produced a picture.
bool surfacePlaybackError({required bool framesVisible}) => !framesVisible;

/// Messages that mean the file itself did not open.
///
/// Decoder hiccups and short read errors are not in this list: media_kit
/// forwards every mpv error-level log, including ones that still play.
bool hardPlaybackFailure(String message) {
  final text = message.toLowerCase();
  const needles = [
    'failed to recognize file format',
    'failed to open file',
    'protocol not found',
    'http error 401',
    'http error 403',
    'http error 404',
    'server returned 401',
    'server returned 403',
    'server returned 404',
    '403 forbidden',
    '404 not found',
  ];
  return needles.any(text.contains);
}

class PlaybackFallback {
  const PlaybackFallback({
    required this.url,
    required this.label,
    required this.transcode,
  });

  final String url;
  final String label;
  final bool transcode;
}

/// Next URL after the current attempt produced no picture.
///
/// DirectStream / a container-qualified static URL comes before HLS.
PlaybackFallback? choosePlaybackFallback({
  required String currentUrl,
  required bool triedDirect,
  required bool triedTranscode,
  String? directUrl,
  String directLabel = 'DirectStream',
  String? transcodeUrl,
}) {
  final direct = directUrl?.trim() ?? '';
  if (!triedDirect && direct.isNotEmpty && direct != currentUrl) {
    return PlaybackFallback(url: direct, label: directLabel, transcode: false);
  }
  final transcode = transcodeUrl?.trim() ?? '';
  if (!triedTranscode && transcode.isNotEmpty && transcode != currentUrl) {
    return PlaybackFallback(url: transcode, label: '转码', transcode: true);
  }
  return null;
}

/// Drop `Accept`, which the API client sets to `application/json`.
Map<String, String> playbackHeaders(Map<String, String> headers) {
  final copy = Map<String, String>.from(headers);
  copy.removeWhere((key, _) => key.toLowerCase() == 'accept');
  return copy;
}
