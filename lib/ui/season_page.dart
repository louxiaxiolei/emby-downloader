import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../downloads/download_service.dart';
import '../emby/api.dart';
import '../emby/models.dart';
import '../emby/urls.dart';
import '../session_controller.dart';
import '../theme.dart';
import 'detail_page.dart';
import 'widgets.dart';

class SeasonPage extends StatefulWidget {
  const SeasonPage({
    super.key,
    required this.seriesId,
    required this.seriesName,
    required this.seasonId,
    required this.seasonName,
  });

  final String seriesId;
  final String seriesName;
  final String seasonId;
  final String seasonName;

  @override
  State<SeasonPage> createState() => _SeasonPageState();
}

class _SeasonPageState extends State<SeasonPage> {
  var _loading = true;
  String? _error;
  List<EmbyItem> _episodes = const [];
  var _batching = false;

  @override
  void initState() {
    super.initState();
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
      final page = await client.episodes(seriesId: widget.seriesId, seasonId: widget.seasonId);
      if (!mounted) return;
      setState(() {
        _episodes = page.items;
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

  Future<void> _downloadAll() async {
    final client = context.read<SessionController>().client;
    if (client == null) return;
    final count = _episodes.where((episode) => episode.canDownload).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载整季'),
        content: Text('将把 $count 集的原始文件加入队列。已经下载或正在下载的会跳过，外挂字幕会一并保存。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('加入队列')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _batching = true);
    final result = await context.read<DownloadService>().enqueueEpisodes(
      client: client,
      episodes: _episodes,
    );
    if (!mounted) return;
    setState(() => _batching = false);
    await showMessage(context, '已加入 ${result.enqueued} 个文件，跳过 ${result.skipped} 项');
  }

  Future<void> _downloadOne(EmbyItem episode) async {
    final client = context.read<SessionController>().client;
    if (client == null) return;
    final result = await context.read<DownloadService>().enqueueItem(
      client: client,
      item: episode,
      source: episode.mediaSources.isEmpty ? null : episode.mediaSources.first,
    );
    if (!mounted) return;
    await showMessage(
      context,
      result.enqueued == 0 ? '这一集已在队列或本地文件中' : '已加入 ${result.enqueued} 个文件',
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<SessionController>().client;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.seasonName),
            if (widget.seriesName.isNotEmpty)
              Text(
                widget.seriesName,
                style: const TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w400),
              ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? LoadError(message: _error!, onRetry: _load)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: FilledButton.icon(
                    onPressed: _batching || _episodes.isEmpty ? null : _downloadAll,
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(_batching ? '正在加入队列' : '下载整季'),
                  ),
                ),
                Expanded(
                  child: _episodes.isEmpty
                      ? const EmptyHint(message: '这一季没有剧集')
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                          itemCount: _episodes.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final episode = _episodes[index];
                            final code = episodeCode(episode) ?? '';
                            return ListTile(
                              leading: Poster(
                                url: client?.imageUrl(episode, maxHeight: 180) ?? '',
                                headers: client?.headers ?? const {},
                                width: 96,
                                height: 54,
                              ),
                              title: Text(
                                code.isEmpty ? episode.name : '$code  ${episode.name}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  formatRuntime(episode.runTimeTicks),
                                  episode.canDownload ? '' : '没有文件',
                                ].where((part) => part.isNotEmpty).join(' · '),
                                style: const TextStyle(color: muted),
                              ),
                              trailing: IconButton(
                                tooltip: '下载这一集',
                                onPressed: episode.canDownload ? () => _downloadOne(episode) : null,
                                icon: const Icon(Icons.download),
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => DetailPage(itemId: episode.id, hint: episode),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
