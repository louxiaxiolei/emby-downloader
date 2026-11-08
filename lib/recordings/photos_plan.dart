/// How a recording is prepared for the system photo library.
enum PhotosSaveKind {
  /// mp4/mov with a Photos-friendly codec. Save the file as-is.
  direct,

  /// Copy packets into mp4. HEVC is tagged hvc1.
  remux,

  /// Copy the video and encode only the audio as AAC.
  transcodeAudio,

  /// Encode video as H.264 and audio as AAC.
  transcodeVideo,
}

class PhotosSavePlan {
  const PhotosSavePlan({required this.kind, required this.message});

  final PhotosSaveKind kind;

  /// Snackbar after a successful save.
  final String message;
}

bool photosVideoCodec(String codec) {
  final text = codec.toLowerCase();
  return text.contains('h264') || text.contains('avc') || text.contains('hevc') || text.contains('h265');
}

bool hevcVideoCodec(String codec) {
  final text = codec.toLowerCase();
  return text.contains('hevc') || text.contains('h265');
}

bool photosAudioCodec(String codec) {
  final text = codec.toLowerCase();
  if (text.trim().isEmpty || text == 'none' || text == 'no') return true;
  return text.contains('aac') || text.contains('mp4a') || text.contains('alac') || text.contains('mp3');
}

bool photosContainer(String extension) {
  final text = extension.toLowerCase().replaceAll('.', '');
  return text == 'mp4' || text == 'm4v' || text == 'mov';
}

PhotosSavePlan planPhotosSave({
  required String extension,
  required String videoCodec,
  required String audioCodec,
}) {
  final videoKnown = videoCodec.trim().isNotEmpty;
  final audioKnown = audioCodec.trim().isNotEmpty;
  final videoOk = !videoKnown || photosVideoCodec(videoCodec);
  final audioOk = !audioKnown || photosAudioCodec(audioCodec);
  final containerOk = photosContainer(extension);
  if (videoKnown && !videoOk) {
    return const PhotosSavePlan(
      kind: PhotosSaveKind.transcodeVideo,
      message: '这个编码相册不能直接存，已转成 H.264/AAC',
    );
  }
  if (audioKnown && !audioOk) {
    return const PhotosSavePlan(
      kind: PhotosSaveKind.transcodeAudio,
      message: '视频已原样复制，音频转成了 AAC，并保存到相册',
    );
  }
  if (!containerOk || hevcVideoCodec(videoCodec)) {
    return const PhotosSavePlan(
      kind: PhotosSaveKind.remux,
      message: '已重新封装为 MP4 并保存到相册',
    );
  }
  return const PhotosSavePlan(
    kind: PhotosSaveKind.direct,
    message: '已保存到相册',
  );
}
