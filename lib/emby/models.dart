class EmbySession {
  const EmbySession({
    required this.base,
    required this.apiPrefix,
    required this.serverName,
    required this.serverId,
    required this.serverVersion,
    required this.userId,
    required this.username,
    required this.accessToken,
    required this.allowBadCertificate,
  });

  /// Server origin plus any reverse-proxy path, without a trailing slash
  /// and without the `/emby` API prefix.
  final String base;
  final String apiPrefix;
  final String serverName;
  final String serverId;
  final String serverVersion;
  final String userId;
  final String username;
  final String accessToken;
  final bool allowBadCertificate;

  String get apiRoot => '$base$apiPrefix';

  Map<String, dynamic> toJson() => {
    'base': base,
    'apiPrefix': apiPrefix,
    'serverName': serverName,
    'serverId': serverId,
    'serverVersion': serverVersion,
    'userId': userId,
    'username': username,
    'accessToken': accessToken,
    'allowBadCertificate': allowBadCertificate,
  };

  factory EmbySession.fromJson(Map<String, dynamic> json) {
    return EmbySession(
      base: json['base'] as String,
      apiPrefix: json['apiPrefix'] as String? ?? '/emby',
      serverName: json['serverName'] as String? ?? 'Emby',
      serverId: json['serverId'] as String? ?? '',
      serverVersion: json['serverVersion'] as String? ?? '',
      userId: json['userId'] as String,
      username: json['username'] as String? ?? '',
      accessToken: json['accessToken'] as String,
      allowBadCertificate: json['allowBadCertificate'] as bool? ?? false,
    );
  }
}

class EmbyPerson {
  const EmbyPerson({required this.name, this.type, this.role, this.id, this.primaryTag});

  final String name;
  final String? type;
  final String? role;
  final String? id;
  final String? primaryTag;

  factory EmbyPerson.fromJson(Map<String, dynamic> json) {
    return EmbyPerson(
      name: json['Name'] as String? ?? '',
      type: json['Type'] as String?,
      role: json['Role'] as String?,
      id: json['Id'] as String?,
      primaryTag: json['PrimaryImageTag'] as String?,
    );
  }
}

class EmbyStream {
  const EmbyStream({
    required this.index,
    required this.type,
    this.codec,
    this.language,
    this.displayTitle,
    this.isExternal = false,
    this.isTextSubtitleStream = false,
    this.deliveryUrl,
    this.isDefault = false,
    this.width,
    this.height,
  });

  final int index;
  final String type;
  final String? codec;
  final String? language;
  final String? displayTitle;
  final bool isExternal;
  final bool isTextSubtitleStream;
  final String? deliveryUrl;
  final bool isDefault;
  final int? width;
  final int? height;

  bool get isExternalSubtitle => type == 'Subtitle' && isExternal;

  factory EmbyStream.fromJson(Map<String, dynamic> json) {
    return EmbyStream(
      index: (json['Index'] as num?)?.toInt() ?? 0,
      type: json['Type'] as String? ?? '',
      codec: json['Codec'] as String?,
      language: json['Language'] as String?,
      displayTitle: json['DisplayTitle'] as String? ?? json['Title'] as String?,
      isExternal: json['IsExternal'] as bool? ?? false,
      isTextSubtitleStream: json['IsTextSubtitleStream'] as bool? ?? false,
      deliveryUrl: json['DeliveryUrl'] as String?,
      isDefault: json['IsDefault'] as bool? ?? false,
      width: (json['Width'] as num?)?.toInt(),
      height: (json['Height'] as num?)?.toInt(),
    );
  }
}

class EmbyMediaSource {
  const EmbyMediaSource({
    required this.id,
    this.name,
    this.path,
    this.container,
    this.size,
    this.bitrate,
    this.streams = const [],
  });

  final String id;
  final String? name;
  final String? path;
  final String? container;
  final int? size;
  final int? bitrate;
  final List<EmbyStream> streams;

  List<EmbyStream> get externalSubtitles =>
      streams.where((stream) => stream.isExternalSubtitle).toList();

  EmbyMediaSource withStreams(List<EmbyStream> streams) {
    return EmbyMediaSource(
      id: id,
      name: name,
      path: path,
      container: container,
      size: size,
      bitrate: bitrate,
      streams: streams,
    );
  }

  factory EmbyMediaSource.fromJson(Map<String, dynamic> json) {
    return EmbyMediaSource(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String?,
      path: json['Path'] as String?,
      container: json['Container'] as String?,
      size: (json['Size'] as num?)?.toInt(),
      bitrate: (json['Bitrate'] as num?)?.toInt(),
      streams: _streamsFrom(json['MediaStreams']),
    );
  }
}

class EmbyItem {
  const EmbyItem({
    required this.id,
    required this.name,
    required this.type,
    this.collectionType,
    this.overview,
    this.productionYear,
    this.primaryTag,
    this.backdropTag,
    this.logoTag,
    this.communityRating,
    this.runTimeTicks,
    this.genres = const [],
    this.indexNumber,
    this.parentIndexNumber,
    this.seriesName,
    this.seriesId,
    this.seasonId,
    this.seasonName,
    this.childCount,
    this.isFolder = false,
    this.officialRating,
    this.criticRating,
    this.premiereDate,
    this.productionLocations = const [],
    this.path,
    this.locationType,
    this.mediaSources = const [],
    this.people = const [],
    this.playbackPositionTicks,
    this.lastPlayed,
  });

  final String id;
  final String name;
  final String type;
  final String? collectionType;
  final String? overview;
  final int? productionYear;
  final String? primaryTag;
  final String? backdropTag;
  final String? logoTag;
  final double? communityRating;
  final int? runTimeTicks;
  final List<String> genres;
  final int? indexNumber;
  final int? parentIndexNumber;
  final String? seriesName;
  final String? seriesId;
  final String? seasonId;
  final String? seasonName;
  final int? childCount;
  final bool isFolder;
  final String? officialRating;
  final double? criticRating;
  final String? premiereDate;
  final List<String> productionLocations;
  final String? path;
  final String? locationType;
  final List<EmbyMediaSource> mediaSources;
  final List<EmbyPerson> people;

  /// From `UserData.PlaybackPositionTicks`, when the user endpoint returns it.
  final int? playbackPositionTicks;
  final DateTime? lastPlayed;

  double? get watchFraction {
    final ticks = playbackPositionTicks;
    final total = runTimeTicks;
    if (ticks == null || total == null || total <= 0 || ticks <= 0) return null;
    return (ticks / total).clamp(0.0, 1.0).toDouble();
  }

  bool get isVirtual => locationType == 'Virtual';

  bool get canDownload {
    if (id.isEmpty || isVirtual) return false;
    const fileTypes = {
      'Movie',
      'Episode',
      'Video',
      'Audio',
      'MusicVideo',
      'Trailer',
      'AudioBook',
    };
    return fileTypes.contains(type);
  }

  bool get opensAsFolder {
    if (canDownload) return false;
    return isFolder ||
        type == 'CollectionFolder' ||
        type == 'Folder' ||
        type == 'BoxSet' ||
        type == 'CollectionFolder' ||
        type == 'Playlist' ||
        type == 'Genre' ||
        type == 'Studio' ||
        type == 'MusicAlbum' ||
        type == 'Season';
  }

  factory EmbyItem.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'];
    String? primary;
    if (imageTags is Map && imageTags['Primary'] is String) {
      primary = imageTags['Primary'] as String;
    }
    final backdrops = json['BackdropImageTags'];
    String? backdrop;
    if (backdrops is List && backdrops.isNotEmpty) {
      final first = backdrops.first;
      if (first is String) backdrop = first;
    }
    String? logo;
    if (imageTags is Map && imageTags['Logo'] is String) {
      logo = imageTags['Logo'] as String;
    }
    final userData = json['UserData'];
    int? playbackTicks;
    DateTime? lastPlayed;
    if (userData is Map) {
      playbackTicks = (userData['PlaybackPositionTicks'] as num?)?.toInt();
      lastPlayed = DateTime.tryParse(userData['LastPlayedDate']?.toString() ?? '');
    }
    final itemStreams = _streamsFrom(json['MediaStreams']);
    var sources = _sourcesFrom(json['MediaSources']);
    if (sources.isNotEmpty &&
        sources.every((source) => source.streams.isEmpty) &&
        itemStreams.isNotEmpty) {
      sources = [
        for (final source in sources) source.withStreams(itemStreams),
      ];
    }
    return EmbyItem(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '未命名',
      type: json['Type'] as String? ?? '',
      collectionType: json['CollectionType'] as String?,
      overview: json['Overview'] as String?,
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      primaryTag: primary,
      backdropTag: backdrop,
      logoTag: logo,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      genres: [
        for (final genre in (json['Genres'] as List?) ?? const [])
          if (genre is String) genre,
      ],
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      seriesName: json['SeriesName'] as String?,
      seriesId: json['SeriesId'] as String?,
      seasonId: json['SeasonId'] as String?,
      seasonName: json['SeasonName'] as String?,
      childCount: (json['ChildCount'] as num?)?.toInt(),
      isFolder: json['IsFolder'] as bool? ?? false,
      officialRating: json['OfficialRating'] as String?,
      criticRating: (json['CriticRating'] as num?)?.toDouble(),
      premiereDate: json['PremiereDate'] as String?,
      productionLocations: [
        for (final place in (json['ProductionLocations'] as List?) ?? const [])
          if (place is String && place.isNotEmpty) place,
      ],
      path: json['Path'] as String?,
      locationType: json['LocationType'] as String?,
      mediaSources: sources,
      people: [
        for (final person in (json['People'] as List?) ?? const [])
          if (person is Map<String, dynamic>) EmbyPerson.fromJson(person),
      ],
      playbackPositionTicks: playbackTicks,
      lastPlayed: lastPlayed,
    );
  }
}

class EmbyPage {
  const EmbyPage({required this.items, required this.total});

  final List<EmbyItem> items;
  final int total;

  factory EmbyPage.fromJson(Map<String, dynamic> json) {
    final items = [
      for (final item in (json['Items'] as List?) ?? const [])
        if (item is Map<String, dynamic>) EmbyItem.fromJson(item),
    ];
    final total = (json['TotalRecordCount'] as num?)?.toInt() ?? items.length;
    return EmbyPage(items: items, total: total);
  }
}

class EmbyException implements Exception {
  EmbyException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class EmbyUnauthorized extends EmbyException {
  EmbyUnauthorized() : super('登录已失效，请重新登录', statusCode: 401);
}

List<EmbyStream> _streamsFrom(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final stream in raw)
      if (stream is Map<String, dynamic>) EmbyStream.fromJson(stream),
  ];
}

List<EmbyMediaSource> _sourcesFrom(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final source in raw)
      if (source is Map<String, dynamic>) EmbyMediaSource.fromJson(source),
  ];
}
