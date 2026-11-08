import '../emby/models.dart';

/// Series or movie name, without the episode code.
String recordingTitle(EmbyItem item) {
  if (item.type == 'Episode' && (item.seriesName ?? '').isNotEmpty) return item.seriesName!;
  return item.name;
}

/// `《片名》S01E01_00-12-34_00-13-10.mkv`
String recordingFileName({
  required String title,
  String? episode,
  required Duration start,
  required Duration end,
  String extension = 'mkv',
}) {
  final clean = _safeTitle(title);
  final code = (episode ?? '').replaceAll(RegExp(r'\s+'), '');
  final ext = extension.replaceAll('.', '').toLowerCase();
  final suffix = ext.isEmpty ? 'mkv' : ext;
  return '$clean${code}_${_stamp(start)}_${_stamp(end)}.$suffix';
}

/// Container extension from a playback URL, or mkv when the source has none.
String sourceContainer(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final dot = path.lastIndexOf('.');
  if (dot <= 0 || dot == path.length - 1) return 'mkv';
  final ext = path.substring(dot + 1).toLowerCase();
  const known = {
    'mkv',
    'mp4',
    'm4v',
    'mov',
    'ts',
    'm2ts',
    'webm',
    'avi',
    'mpg',
    'mpeg',
  };
  return known.contains(ext) ? ext : 'mkv';
}

String _stamp(Duration position) {
  final total = position.inSeconds < 0 ? 0 : position.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(hours)}-${two(minutes)}-${two(seconds)}';
}

String _safeTitle(String title) {
  var text = title.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001F]'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) text = '未命名';
  if (!text.startsWith('《')) text = '《$text》';
  if (text.length > 80) text = text.substring(0, 80).trim();
  return text;
}
