import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../downloads/download_service.dart';
import '../recordings/recordings_section.dart';
import '../downloads/speed.dart';
import '../emby/models.dart';
import '../emby/playback.dart';
import '../emby/urls.dart';
import '../session_controller.dart';
import '../storage/settings_store.dart';
import '../theme.dart';
import 'chrome.dart';
import 'player_page.dart';
import 'widgets.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    final settings = context.watch<SettingsStore>();
    final cinema = context.cinema;
    final groups = <String, List<LocalFile>>{};
    for (final file in downloads.files) {
      groups.putIfAbsent(file.itemId, () => []).add(file);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载'),
        leading: Navigator.of(context).canPop()
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GlassButton(icon: Icons.arrow_back, onPressed: () => Navigator.of(context).maybePop()),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (downloads.initError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(downloads.initError!, style: const TextStyle(color: danger)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.wifiOnly,
            title: const Text('仅使用 Wi-Fi'),
            subtitle: Text('对新加入的任务生效', style: TextStyle(color: cinema.muted, fontSize: 12)),
            onChanged: settings.setWifiOnly,
          ),
          if (!kIsWeb && Platform.isAndroid)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.publicDownloads,
              title: const Text('完成后保存到系统下载目录'),
              onChanged: settings.setPublicDownloads,
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.saveRecordingsToPhotos,
            title: const Text('录完自动保存到相册'),
            subtitle: Text('MKV 会先封装成 MP4。不支持的编码会转码。', style: TextStyle(color: cinema.muted, fontSize: 12)),
            onChanged: settings.setSaveRecordingsToPhotos,
          ),
          const SizedBox(height: 8),
          Text('进行中', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cinema.text)),
          const SizedBox(height: 8),
          if (downloads.live.isEmpty)
            Text('队列是空的', style: TextStyle(color: cinema.muted))
          else
            ...downloads.live.map((item) => _LiveCard(item: item)),
          const SizedBox(height: 18),
          const RecordingsSection(),
          const SizedBox(height: 18),
          Text('已保存', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cinema.text)),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            Text('还没有下载完成的文件', style: TextStyle(color: cinema.muted))
          else
            ...groups.entries.map((entry) => _SavedCard(files: entry.value)),
        ],
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.item});

  final LiveDownload item;

  @override
  Widget build(BuildContext context) {
    final cinema = context.cinema;
    final showBar = item.status == TaskStatus.running || item.status == TaskStatus.paused;
    final speed = item.speedLabel;
    final remaining = item.remainingLabel;
    final detail = [
      _statusLabel(item),
      if (item.meta.kind == 'subtitle') '字幕',
      if (speed != null && speed.isNotEmpty && item.status == TaskStatus.running) speed,
      if (remaining != null && remaining.isNotEmpty && item.status == TaskStatus.running) '剩余 $remaining',
      if (item.error != null && item.error!.isNotEmpty) item.error!,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 54,
                    height: 78,
                    child: EmbyImage(url: item.meta.imageUrl ?? '', headers: const {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.task.displayName.isEmpty ? item.task.filename : item.task.displayName, maxLines: 2),
                      const SizedBox(height: 4),
                      Text(detail, style: TextStyle(color: cinema.muted, fontSize: 12)),
                      if (showBar) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progressBarValue(item.progress),
                          minHeight: 4,
                          color: okGreen,
                          backgroundColor: cinema.line,
                        ),
                        const SizedBox(height: 4),
                        Text(progressLabel(item.progress), style: TextStyle(color: cinema.muted, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (item.status == TaskStatus.running)
                  TextButton(onPressed: () => context.read<DownloadService>().pause(item.task), child: const Text('暂停')),
                if (item.status == TaskStatus.paused)
                  TextButton(onPressed: () => context.read<DownloadService>().resume(item.task), child: const Text('继续')),
                if (item.status == TaskStatus.failed || item.status == TaskStatus.notFound)
                  TextButton(onPressed: () => context.read<DownloadService>().retry(item), child: const Text('重试')),
                if (item.active)
                  TextButton(onPressed: () => _cancel(context, item), child: const Text('取消')),
                if (!item.active)
                  TextButton(onPressed: () => context.read<DownloadService>().dismiss(item), child: const Text('移除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, LiveDownload item) async {
    final downloads = context.read<DownloadService>();
    final name = item.task.displayName.isEmpty ? item.task.filename : item.task.displayName;
    final task = await downloads.cancel(item);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已取消「$name」'),
        action: SnackBarAction(label: '撤销', onPressed: () => downloads.undoCancel(task)),
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  const _SavedCard({required this.files});

  final List<LocalFile> files;

  @override
  Widget build(BuildContext context) {
    final cinema = context.cinema;
    final video = files.where((file) => file.kind == 'video');
    final main = video.isEmpty ? files.first : video.first;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 48,
            height: 68,
            child: EmbyImage(url: '', headers: const {}),
          ),
        ),
        title: Text(main.title.isEmpty ? main.filename : main.title, maxLines: 2),
        subtitle: Text(
          [main.filename, formatBytes(main.bytes), formatWhen(main.savedAt)].where((part) => part.isNotEmpty).join('\n'),
          style: TextStyle(color: cinema.muted, fontSize: 12, height: 1.35),
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '播放',
              onPressed: main.kind == 'video' ? () => _playSaved(context, files) : null,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('删除本地文件'),
                    content: const Text('会删除这个条目的视频和外挂字幕。服务器上的文件不受影响。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await context.read<DownloadService>().deleteItem(main.itemId);
                }
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _playSaved(BuildContext context, List<LocalFile> group) async {
  final downloads = context.read<DownloadService>();
  final video = group.where((file) => file.kind == 'video');
  final main = video.isEmpty ? group.first : video.first;
  final path = await downloads.readableFilePath(main);
  if (!context.mounted) return;
  if (path == null) {
    final message = await downloads.openFile(main);
    if (message != null && context.mounted) await showMessage(context, message);
    return;
  }
  final subtitles = <PlaybackSubtitle>[];
  for (final file in group) {
    if (file.kind != 'subtitle') continue;
    final subtitlePath = await downloads.readableFilePath(file);
    if (subtitlePath == null) continue;
    subtitles.add(
      PlaybackSubtitle(
        title: file.title.isEmpty ? file.filename : file.title,
        url: Uri.file(subtitlePath).toString(),
      ),
    );
  }
  if (!context.mounted) return;
  final client = context.read<SessionController>().client;
  Duration? resume;
  if (client != null && main.itemId.isNotEmpty) {
    try {
      final item = await client.item(main.itemId);
      resume = resumePosition(item.playbackPositionTicks, item.runTimeTicks);
    } on EmbyUnauthorized {
      if (context.mounted) {
        await context.read<SessionController>().invalidate();
        if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    } catch (_) {}
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerPage(
        title: main.title.isEmpty ? main.filename : main.title,
        itemId: main.itemId,
        playback: ResolvedPlayback(
          url: Uri.file(path).toString(),
          playMethod: 'DirectPlay',
          headers: client?.headers ?? const {},
          playSessionId: main.itemId.isEmpty ? null : 'local-${main.itemId}',
          mediaSourceId: main.itemId,
          subtitles: subtitles,
          resume: resume,
        ),
      ),
    ),
  );
}

String _statusLabel(LiveDownload item) {
  return switch (item.status) {
    TaskStatus.enqueued => '等待中',
    TaskStatus.running => '下载中',
    TaskStatus.paused => '已暂停',
    TaskStatus.waitingToRetry => '稍后重试',
    TaskStatus.failed => '失败',
    TaskStatus.notFound => '找不到文件，已尝试备用地址',
    TaskStatus.complete => '已完成',
    TaskStatus.canceled => '已取消',
  };
}
