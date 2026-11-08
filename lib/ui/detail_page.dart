import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../downloads/download_service.dart';
import '../emby/api.dart';
import '../emby/models.dart';
import '../emby/playback.dart';
import '../emby/urls.dart';
import '../session_controller.dart';
import '../theme.dart';
import 'player_page.dart';
import 'season_page.dart';
import 'widgets.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.itemId, this.hint});

  final String itemId;
  final EmbyItem? hint;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  EmbyItem? _item;
  List<EmbyItem> _seasons = const [];
  var _loading = true;
  String? _error;
  var _sourceIndex = 0;
  var _downloading = false;
  var _playing = false;

  @override
  void initState() {
    super.initState();
    _item = widget.hint;
    _load();
  }

  Future<void> _load() async {
    final client = context.read<SessionController>().client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await client.item(widget.itemId);
      final seasons = item.type == 'Series' ? await client.seasons(item.id) : null;
      if (!mounted) return;
      setState(() {
        _item = item;
        _seasons = seasons?.items ?? const [];
        _loading = false;
      });
    } on EmbyUnauthorized {
      if (!mounted) return;
      await context.read<SessionController>().invalidate();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(error);
        _loading = false;
      });
    }
  }

  Future<void> _play(EmbyItem item) async {
    if (_playing) return;
    final client = context.read<SessionController>().client;
    if (client == null) return;
    final source = item.mediaSources.isEmpty
        ? null
        : item.mediaSources[_sourceIndex.clamp(0, item.mediaSources.length - 1)];
    setState(() => _playing = true);
    try {
      Map<String, dynamic>? info;
      try {
        info = await client.playbackInfo(
          itemId: item.id,
          mediaSourceId: source?.id,
          startTimeTicks: item.playbackPositionTicks ?? 0,
        );
      } on EmbyUnauthorized {
        rethrow;
      } catch (_) {
        info = null;
      }
      final playback = resolvePlayback(
        base: client.session.base,
        apiRoot: client.session.apiRoot,
        accessToken: client.session.accessToken,
        itemId: item.id,
        mediaSourceId: source?.id,
        container: source?.container,
        playbackInfo: info,
        knownStreams: source?.streams ?? const [],
        resume: resumePosition(item.playbackPositionTicks, item.runTimeTicks),
        headers: client.headers,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerPage(title: mediaTitle(item), itemId: item.id, playback: playback),
        ),
      );
    } on EmbyUnauthorized {
      if (!mounted) return;
      await context.read<SessionController>().invalidate();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) await showMessage(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _download(EmbyItem item) async {
    if (_downloading) return;
    final client = context.read<SessionController>().client;
    if (client == null) return;
    final source = item.mediaSources.isEmpty
        ? null
        : item.mediaSources[_sourceIndex.clamp(0, item.mediaSources.length - 1)];
    setState(() => _downloading = true);
    final result = await context.read<DownloadService>().enqueueItem(
      client: client,
      item: item,
      source: source,
    );
    if (!mounted) return;
    setState(() => _downloading = false);
    final message = result.enqueued == 0
        ? '没有加入队列。可能已经下载过，或这一项没有可下载的文件。'
        : '已加入 ${result.enqueued} 个文件';
    await showMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<SessionController>().client;
    final item = _item;
    return Scaffold(
      body: _loading && item == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && item == null
          ? LoadError(message: _error!, onRetry: _load)
          : item == null
          ? const EmptyHint(message: '找不到这个条目')
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 220,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    background: _backdrop(client, item),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _meta(item),
                        if ((item.overview ?? '').isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(item.overview!, style: const TextStyle(height: 1.5, color: ivory)),
                        ],
                        if (item.type == 'Series') ...[
                          const SizedBox(height: 22),
                          const Text('季', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          if (_seasons.isEmpty)
                            const Text('没有季信息', style: TextStyle(color: muted))
                          else
                            ..._seasons.map((season) => _seasonTile(item, season, client)),
                        ] else if (item.canDownload) ...[
                          const SizedBox(height: 18),
                          _sourcePicker(item),
                          const SizedBox(height: 12),
                          _subtitleList(item),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _playing ? null : () => _play(item),
                            icon: _playing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: const Text('播放'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _downloading ? null : () => _download(item),
                            icon: _downloading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.download),
                            label: const Text('下载原始文件'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _backdrop(client, EmbyItem item) {
    final url = client?.imageUrl(item, type: 'Backdrop', maxWidth: 1280) ?? '';
    final fallback = url.isEmpty ? (client?.imageUrl(item, maxHeight: 600) ?? '') : url;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (fallback.isNotEmpty)
          CachedNetworkImage(
            imageUrl: fallback,
            httpHeaders: client?.headers ?? const {},
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => const ColoredBox(color: panel),
          )
        else
          const ColoredBox(color: panel),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), ink],
            ),
          ),
        ),
      ],
    );
  }

  Widget _meta(EmbyItem item) {
    final bits = <String>[
      if (item.productionYear != null) '${item.productionYear}',
      if (formatRuntime(item.runTimeTicks).isNotEmpty) formatRuntime(item.runTimeTicks),
      if (item.officialRating != null) item.officialRating!,
      if (item.communityRating != null) '评分 ${item.communityRating!.toStringAsFixed(1)}',
      if (episodeCode(item) != null) episodeCode(item)!,
    ];
    final directors = item.people.where((person) => person.type == 'Director').map((person) => person.name);
    final actors = item.people.where((person) => person.type == 'Actor').take(4).map((person) => person.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.seriesName != null)
          Text(item.seriesName!, style: const TextStyle(color: brass, fontWeight: FontWeight.w700)),
        if (bits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(bits.join('  ·  '), style: const TextStyle(color: muted)),
          ),
        if (item.genres.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final genre in item.genres)
                  Chip(
                    label: Text(genre),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: panelHigh,
                    side: BorderSide.none,
                  ),
              ],
            ),
          ),
        if (directors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('导演  ${directors.join('、')}', style: const TextStyle(color: muted)),
          ),
        if (actors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('主演  ${actors.join('、')}', style: const TextStyle(color: muted)),
          ),
      ],
    );
  }

  Widget _sourcePicker(EmbyItem item) {
    if (item.mediaSources.length <= 1) {
      final summary = videoSummary(item.mediaSources.isEmpty ? null : item.mediaSources.first);
      final size = formatBytes(item.mediaSources.isEmpty ? null : item.mediaSources.first.size);
      final text = [summary, size].where((part) => part != null && part.isNotEmpty).join('  ·  ');
      if (text.isEmpty) return const SizedBox.shrink();
      return Text(text, style: const TextStyle(color: muted));
    }
    return DropdownButtonFormField<int>(
      initialValue: _sourceIndex,
      decoration: const InputDecoration(labelText: '版本'),
      items: [
        for (var i = 0; i < item.mediaSources.length; i++)
          DropdownMenuItem(
            value: i,
            child: Text(
              [
                item.mediaSources[i].name ?? '版本 ${i + 1}',
                formatBytes(item.mediaSources[i].size),
              ].where((part) => part.isNotEmpty).join(' · '),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _sourceIndex = value);
      },
    );
  }

  Widget _subtitleList(EmbyItem item) {
    final source = item.mediaSources.isEmpty
        ? null
        : item.mediaSources[_sourceIndex.clamp(0, item.mediaSources.length - 1)];
    final subtitles = source?.externalSubtitles ?? const [];
    if (subtitles.isEmpty) {
      return const Text('没有单独的外挂字幕。内嵌字幕会随原始文件一起保存。', style: TextStyle(color: muted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('外挂字幕会一起下载', style: TextStyle(color: muted)),
        const SizedBox(height: 6),
        for (final stream in subtitles)
          Text(
            '· ${stream.displayTitle ?? stream.language ?? '字幕'}',
            style: const TextStyle(height: 1.4),
          ),
      ],
    );
  }

  Widget _seasonTile(EmbyItem series, EmbyItem season, client) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Poster(
        url: client?.imageUrl(season, maxHeight: 160) ?? '',
        headers: client?.headers ?? const {},
        width: 48,
        height: 64,
      ),
      title: Text(season.name),
      subtitle: Text(season.childCount == null ? '' : '${season.childCount} 集'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SeasonPage(
              seriesId: series.id,
              seriesName: series.name,
              seasonId: season.id,
              seasonName: season.name,
            ),
          ),
        );
      },
    );
  }
}
