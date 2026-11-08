import 'dart:convert';

import 'models.dart';
import 'urls.dart';

class PlannedDownload {
  const PlannedDownload({
    required this.filename,
    required this.directory,
    required this.displayName,
    required this.itemId,
    required this.kind,
    required this.title,
    required this.urls,
  });

  final String filename;
  final String directory;
  final String displayName;
  final String itemId;
  final String kind;
  final String title;

  /// First URL is `/Items/{Id}/Download`. Later entries are fallbacks.
  final List<String> urls;
}

class DownloadMeta {
  const DownloadMeta({
    required this.kind,
    required this.itemId,
    required this.title,
    required this.stage,
    required this.urls,
  });

  final String kind;
  final String itemId;
  final String title;
  final int stage;
  final List<String> urls;

  DownloadMeta copyWith({int? stage}) {
    return DownloadMeta(
      kind: kind,
      itemId: itemId,
      title: title,
      stage: stage ?? this.stage,
      urls: urls,
    );
  }

  String encode() => jsonEncode({
    'kind': kind,
    'itemId': itemId,
    'title': title,
    'stage': stage,
    'urls': urls,
  });

  factory DownloadMeta.decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        return DownloadMeta(
          kind: json['kind'] as String? ?? 'video',
          itemId: json['itemId'] as String? ?? '',
          title: json['title'] as String? ?? '',
          stage: (json['stage'] as num?)?.toInt() ?? 0,
          urls: [
            for (final url in (json['urls'] as List?) ?? const []) url.toString(),
          ],
        );
      }
    } catch (_) {}
    return const DownloadMeta(
      kind: 'video',
      itemId: '',
      title: '',
      stage: 0,
      urls: [],
    );
  }
}

/// Builds the original-file download plus external subtitles.
///
/// Embedded subtitles stay inside the original file, so only `IsExternal`
/// tracks are fetched. Text tracks use the documented `.srt` conversion.
List<PlannedDownload> planItemDownload({
  required String apiRoot,
  required String accessToken,
  required EmbyItem item,
  EmbyMediaSource? source,
  Set<String>? usedNames,
}) {
  final names = usedNames ?? <String>{};
  final sourceId = (source != null && source.id.isNotEmpty) ? source.id : item.id;
  final directory = mediaDirectory(item);
  final videoName = uniqueFileName(videoFileName(item, source), names);
  final title = mediaTitle(item);
  final playSession = 'dl${item.id.hashCode.abs()}';
  final urls = <String>[
    itemDownloadUri(
      apiRoot: apiRoot,
      itemId: item.id,
      accessToken: accessToken,
      mediaSourceId: source?.id,
    ).toString(),
    staticStreamUri(
      apiRoot: apiRoot,
      itemId: item.id,
      accessToken: accessToken,
      mediaSourceId: sourceId,
      container: source?.container,
      playSessionId: playSession,
    ).toString(),
    itemFileUri(
      apiRoot: apiRoot,
      itemId: item.id,
      accessToken: accessToken,
    ).toString(),
  ];
  final plans = <PlannedDownload>[
    PlannedDownload(
      filename: videoName,
      directory: directory,
      displayName: title,
      itemId: item.id,
      kind: 'video',
      title: title,
      urls: urls,
    ),
  ];
  final subtitles = source?.externalSubtitles ?? const <EmbyStream>[];
  final seen = <String>{};
  for (final stream in subtitles) {
    if (sourceId.isEmpty) continue;
    var subtitleName = subtitleFileName(videoName, stream);
    if (!seen.add(subtitleName)) {
      subtitleName = subtitleFileName(videoName, stream, withIndex: true);
      seen.add(subtitleName);
    }
    subtitleName = uniqueFileName(subtitleName, names);
    final format = stream.isTextSubtitleStream
        ? 'srt'
        : (cleanContainer(stream.codec) ?? 'sub');
    plans.add(
      PlannedDownload(
        filename: subtitleName,
        directory: directory,
        displayName: '$title 字幕',
        itemId: item.id,
        kind: 'subtitle',
        title: stream.displayTitle ?? stream.language ?? '字幕',
        urls: [
          subtitleUri(
            apiRoot: apiRoot,
            itemId: item.id,
            mediaSourceId: sourceId,
            index: stream.index,
            format: format,
            accessToken: accessToken,
          ).toString(),
        ],
      ),
    );
  }
  return plans;
}
