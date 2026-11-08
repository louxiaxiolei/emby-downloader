import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../downloads/download_service.dart';
import '../emby/api.dart';
import '../emby/models.dart';
import '../emby/playback.dart';
import '../emby/urls.dart';
import '../session_controller.dart';
import '../theme.dart';
import 'chrome.dart';
import 'home_page.dart';
import 'player_page.dart';
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
  List<EmbyItem> _episodes = const [];
  List<EmbyItem> _similar = const [];
  var _seasonIndex = 0;
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
      _loading = _item == null;
      _error = null;
    });
    try {
      final item = await client.item(widget.itemId);
      final seasons = item.type == 'Series' ? await client.seasons(item.id) : null;
      final similar = await _quiet(() => client.similar(item.id));
      if (!mounted) return;
      setState(() {
        _item = item;
        _seasons = seasons?.items ?? const [];
        _similar = similar;
        _loading = false;
      });
      if (_seasons.isNotEmpty) await _loadEpisodes(0);
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

  Future<List<EmbyItem>> _quiet(Future<List<EmbyItem>> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadEpisodes(int index) async {
    final client = context.read<SessionController>().client;
    final item = _item;
    if (client == null || item == null || index >= _seasons.length) return;
    setState(() => _seasonIndex = index);
    try {
      final page = await client.episodes(seriesId: item.id, seasonId: _seasons[index].id);
      if (!mounted) return;
      setState(() => _episodes = page.items);
    } catch (_) {
      if (mounted) setState(() => _episodes = const []);
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
    final cinema = context.cinema;
    if (_loading && item == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null && item == null) {
      return Scaffold(body: LoadError(message: _error!, onRetry: _load));
    }
    if (item == null) return const Scaffold(body: EmptyHint(message: '找不到这个条目'));
    final backdrop = client?.imageUrl(item, type: 'Backdrop', maxWidth: 1280) ?? '';
    final logo = client?.imageUrl(item, type: 'Logo', maxWidth: 800) ?? '';
    final resume = resumePosition(item.playbackPositionTicks, item.runTimeTicks);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 420,
            pinned: true,
            backgroundColor: cinema.background,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: GlassButton(icon: Icons.arrow_back, onPressed: () => Navigator.of(context).maybePop()),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  EmbyImage(url: backdrop.isEmpty ? (client?.imageUrl(item, maxWidth: 800) ?? '') : backdrop, headers: client?.headers ?? const {}),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x33000000), Color(0x00000000), Color(0xEE101114)],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (logo.isNotEmpty)
                          SizedBox(height: 72, child: EmbyImage(url: logo, headers: client?.headers ?? const {}, fit: BoxFit.contain))
                        else
                          Text(
                            item.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w200, letterSpacing: 2),
                          ),
                        const SizedBox(height: 8),
                        Text(_meta(item), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 8),
                        RatingRow(item: item, onDark: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((item.overview ?? '').isNotEmpty)
                    Text(item.overview!, style: TextStyle(height: 1.5, color: cinema.text)),
                  const SizedBox(height: 16),
                  if (item.canDownload) ...[
                    FilledButton.icon(
                      onPressed: _playing ? null : () => _play(item),
                      icon: _playing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(resume == null ? '播放' : '继续播放'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _downloading ? null : () => _download(item),
                      icon: _downloading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded),
                      label: const Text('下载'),
                    ),
                    const SizedBox(height: 12),
                    _sourceLine(item),
                  ],
                  if (_seasons.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _seasons.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final selected = index == _seasonIndex;
                          return ChoiceChip(
                            label: Text(_seasons[index].name),
                            selected: selected,
                            onSelected: (_) => _loadEpisodes(index),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final episode in _episodes) _episode(episode, client),
                  ],
                  if (item.people.where((person) => person.type == 'Actor').isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text('演职员', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cinema.text)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 110,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final person in item.people.where((person) => person.type == 'Actor').take(16))
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: SizedBox(
                                width: 72,
                                child: Column(
                                  children: [
                                    ClipOval(
                                      child: SizedBox(
                                        width: 64,
                                        height: 64,
                                        child: EmbyImage(
                                          url: client?.personImageUrl(person) ?? '',
                                          headers: client?.headers ?? const {},
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                    Text(
                                      person.role ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: cinema.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (_similar.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('相似内容', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cinema.text)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 180,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _similar.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final other = _similar[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => DetailPage(itemId: other.id, hint: other)),
                              );
                            },
                            child: SizedBox(
                              width: 110,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: EmbyImage(
                                        url: client?.imageUrl(other, maxWidth: 300) ?? '',
                                        headers: client?.headers ?? const {},
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(other.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
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

  String _meta(EmbyItem item) {
    final places = item.productionLocations.take(2).join('/');
    final genres = item.genres.take(3).join(' ');
    final date = (item.premiereDate ?? item.productionYear?.toString() ?? '').split('T').first;
    return [places, genres, date, formatRuntime(item.runTimeTicks)].where((part) => part.isNotEmpty).join(' · ');
  }

  Widget _sourceLine(EmbyItem item) {
    if (item.mediaSources.length <= 1) {
      final text = videoSummary(item.mediaSources.isEmpty ? null : item.mediaSources.first) ?? '';
      if (text.isEmpty) return const SizedBox.shrink();
      return Text(text, style: TextStyle(color: context.cinema.muted, fontSize: 12));
    }
    return DropdownButton<int>(
      value: _sourceIndex.clamp(0, item.mediaSources.length - 1),
      isExpanded: true,
      items: [
        for (var i = 0; i < item.mediaSources.length; i++)
          DropdownMenuItem(value: i, child: Text(item.mediaSources[i].name ?? '版本 ${i + 1}')),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _sourceIndex = value);
      },
    );
  }

  Widget _episode(EmbyItem episode, EmbyClient? client) {
    final fraction = episode.watchFraction;
    final code = episodeCode(episode) ?? '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 112,
          height: 64,
          child: EmbyImage(
            url: client?.imageUrl(episode, type: 'Thumb', maxWidth: 320) ?? '',
            headers: client?.headers ?? const {},
          ),
        ),
      ),
      title: Text(code.isEmpty ? episode.name : '$code  ${episode.name}', maxLines: 2),
      subtitle: fraction == null
          ? Text(formatRuntime(episode.runTimeTicks), style: TextStyle(color: context.cinema.muted, fontSize: 12))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatSeen(episode.playbackPositionTicks), style: TextStyle(color: context.cinema.muted, fontSize: 12)),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: fraction, minHeight: 3),
              ],
            ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => DetailPage(itemId: episode.id, hint: episode)),
        );
      },
    );
  }
}
