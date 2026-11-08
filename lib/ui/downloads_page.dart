import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../downloads/download_service.dart';
import '../emby/urls.dart';
import '../storage/settings_store.dart';
import '../theme.dart';
import 'widgets.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    final settings = context.watch<SettingsStore>();
    final groups = <String, List<LocalFile>>{};
    for (final file in downloads.files) {
      groups.putIfAbsent(file.itemId, () => []).add(file);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('下载')),
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
            subtitle: const Text('对新加入的任务生效', style: TextStyle(color: muted, fontSize: 12)),
            onChanged: (value) {
              settings.setWifiOnly(value);
            },
          ),
          if (!kIsWeb && Platform.isAndroid)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.publicDownloads,
              title: const Text('完成后保存到系统下载目录'),
              subtitle: const Text(
                'Android 会把文件移动到 Download/Emby。关闭时文件留在应用目录，仍可在文件管理器里看到。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              onChanged: (value) {
                settings.setPublicDownloads(value);
              },
            ),
          const SizedBox(height: 8),
          const _SectionTitle('进行中'),
          if (downloads.live.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('队列是空的', style: TextStyle(color: muted)),
            )
          else
            ...downloads.live.map((item) => _LiveTile(item: item)),
          const SizedBox(height: 18),
          const _SectionTitle('已保存'),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('还没有下载完成的文件', style: TextStyle(color: muted)),
            )
          else
            ...groups.entries.map((entry) => _SavedTile(files: entry.value)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}

class _LiveTile extends StatelessWidget {
  const _LiveTile({required this.item});

  final LiveDownload item;

  @override
  Widget build(BuildContext context) {
    final downloads = context.read<DownloadService>();
    final progress = item.progress.clamp(0.0, 1.0);
    final showBar = item.status == TaskStatus.running || item.status == TaskStatus.paused;
    final subtitle = [
      _statusLabel(item),
      if (item.meta.kind == 'subtitle') '字幕',
      if (item.speedLabel != null && item.status == TaskStatus.running) item.speedLabel!,
      if (item.remainingLabel != null && item.status == TaskStatus.running) '剩余 ${item.remainingLabel}',
      if (item.error != null && item.error!.isNotEmpty) item.error!,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.task.displayName.isEmpty ? item.task.filename : item.task.displayName),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
            if (showBar) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: item.progress <= 0 ? null : progress),
              const SizedBox(height: 4),
              Text('${(progress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: muted, fontSize: 12)),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (item.status == TaskStatus.running)
                  TextButton(onPressed: () => downloads.pause(item.task), child: const Text('暂停')),
                if (item.status == TaskStatus.paused)
                  TextButton(onPressed: () => downloads.resume(item.task), child: const Text('继续')),
                if (item.status == TaskStatus.failed || item.status == TaskStatus.notFound)
                  TextButton(onPressed: () => downloads.retry(item), child: const Text('重试')),
                if (item.active)
                  TextButton(onPressed: () => downloads.cancel(item), child: const Text('取消')),
                if (!item.active)
                  TextButton(onPressed: () => downloads.dismiss(item), child: const Text('移除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.files});

  final List<LocalFile> files;

  @override
  Widget build(BuildContext context) {
    final video = files.where((file) => file.kind == 'video');
    final main = video.isEmpty ? files.first : video.first;
    final subtitles = files.where((file) => file.kind == 'subtitle').length;
    final location = main.sharedPath == null ? main.directory : '系统下载目录 / ${main.directory}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(main.title.isEmpty ? main.filename : main.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            main.filename,
            if (formatBytes(main.bytes).isNotEmpty) formatBytes(main.bytes),
            if (subtitles > 0) '外挂字幕 $subtitles',
            formatWhen(main.savedAt),
            location,
          ].where((part) => part.isNotEmpty).join('\n'),
          style: const TextStyle(color: muted, fontSize: 12, height: 1.35),
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 0,
          children: [
            IconButton(
              tooltip: '播放',
              onPressed: main.kind == 'video'
                  ? () async {
                      final message = await context.read<DownloadService>().openFile(main);
                      if (message != null && context.mounted) await showMessage(context, message);
                    }
                  : null,
              icon: const Icon(Icons.play_arrow),
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
