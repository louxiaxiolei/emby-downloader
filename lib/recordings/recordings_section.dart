import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../emby/net_log.dart';
import '../emby/playback.dart';
import '../emby/urls.dart';
import '../theme.dart';
import '../ui/player_page.dart';
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
    _reload();
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
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator(minHeight: 2))
        else if (_files.isEmpty)
          Text('还没有录制。播放时点录制，再点一次停止。', style: TextStyle(color: cinema.muted, fontSize: 12))
        else
          ..._files.map((file) => _tile(context, file)),
      ],
    );
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
              tooltip: file.canOfferPhotos ? '分享，可保存到照片' : '分享到文件',
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
