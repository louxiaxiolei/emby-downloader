import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../emby/net_log.dart';
import '../emby/playback.dart';
import '../emby/urls.dart';
import '../theme.dart';
import '../ui/player_page.dart';
import '../downloads/speed.dart';
import 'clip_queue.dart';
import 'remux.dart';
import 'store.dart';

class RecordingsSection extends StatefulWidget {
  const RecordingsSection({super.key});

  @override
  State<RecordingsSection> createState() => _RecordingsSectionState();
}

class _RecordingsSectionState extends State<RecordingsSection> {
  List<RecordingFile> _files = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    ClipQueue.instance.addListener(_onJobs);
    _reload();
  }

  @override
  void dispose() {
    ClipQueue.instance.removeListener(_onJobs);
    super.dispose();
  }

  void _onJobs() {
    if (!mounted) return;
    setState(() {});
    if (ClipQueue.instance.jobs.any((job) => job.state == ClipJobState.saved)) {
      _reload();
    }
  }

  Future<void> _reload() async {
    try {
      final files = await listRecordings();
      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (error) {
      NetLog.instance.add('读取录制失败 $error');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cinema = context.cinema;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('录制', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cinema.text)),
            const Spacer(),
            IconButton(tooltip: '刷新', onPressed: _reload, icon: const Icon(Icons.refresh)),
          ],
        ),
        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator(minHeight: 2)),
        ...ClipQueue.instance.jobs
            .where((job) => job.state != ClipJobState.saved || !_files.any((file) => file.path == job.path))
            .map((job) => _job(context, job)),
        if (!_loading && _files.isEmpty && ClipQueue.instance.jobs.isEmpty)
          Text('还没有录制。播放时点录制，再点一次停止。', style: TextStyle(color: cinema.muted, fontSize: 12))
        else
          ..._files.map((file) => _tile(context, file)),
      ],
    );
  }

  Widget _job(BuildContext context, ClipJob job) {
    final cinema = context.cinema;
    final failed = job.state == ClipJobState.failed;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatClock(job.start)} – ${formatClock(job.end)}',
              style: TextStyle(color: cinema.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            if (job.state == ClipJobState.running)
              LinearProgressIndicator(value: job.progress <= 0 ? null : job.progress),
            Text(
              job.message,
              style: TextStyle(color: failed ? danger : cinema.text, fontSize: 12),
            ),
          ],
        ),
        trailing: failed
            ? IconButton(
                tooltip: '关闭',
                onPressed: () => ClipQueue.instance.dismiss(job.id),
                icon: const Icon(Icons.close),
              )
            : null,
      ),
    );
  }

  Future<void> _save(RecordingFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在保存到相册')));
    try {
      final message = await saveRecordingToPhotos(file.path);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      NetLog.instance.add('保存到相册失败 $error');
      messenger.showSnackBar(const SnackBar(content: Text('保存到相册失败')));
    }
  }

  Widget _tile(BuildContext context, RecordingFile file) {
    final cinema = context.cinema;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${formatBytes(file.bytes)} · ${formatWhen(file.modified.toIso8601String())}',
          style: TextStyle(color: cinema.muted, fontSize: 12),
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlayerPage(
                title: file.name,
                itemId: '',
                recordTitle: file.name,
                playback: ResolvedPlayback(
                  url: Uri.file(file.path).toString(),
                  playMethod: 'DirectPlay',
                  headers: const {},
                ),
              ),
            ),
          );
        },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '保存到相册',
              visualDensity: VisualDensity.compact,
              onPressed: () => _save(file),
              icon: const Icon(Icons.photo_library_outlined),
            ),
            IconButton(
              tooltip: '分享',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                try {
                  await Share.shareXFiles([XFile(file.path, name: file.name)]);
                  NetLog.instance.add('分享录制 ${file.name}');
                } catch (error) {
                  NetLog.instance.add('分享录制失败 $error');
                }
              },
              icon: const Icon(Icons.ios_share),
            ),
            IconButton(
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                await deleteRecording(file.path);
                NetLog.instance.add('删除录制 ${file.name}');
                await _reload();
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}
