import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../downloads/download_service.dart';
import '../session_controller.dart';
import 'downloads_page.dart';
import 'library_page.dart';
import 'search_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final active = context.watch<DownloadService>().activeCount;
    final pages = const [LibraryPage(), SearchPage(), DownloadsPage()];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: '资料库',
          ),
          const NavigationDestination(
            icon: Icon(Icons.search),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: active > 0,
              label: Text('$active'),
              child: const Icon(Icons.download_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: active > 0,
              label: Text('$active'),
              child: const Icon(Icons.download),
            ),
            label: '下载',
          ),
        ],
      ),
    );
  }
}

Future<void> confirmLogout(BuildContext context) async {
  final session = context.read<SessionController>();
  final should = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('退出登录'),
      content: const Text('本机已经下载的文件会保留。正在进行的下载会被取消。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
      ],
    ),
  );
  if (should != true || !context.mounted) return;
  final downloads = context.read<DownloadService>();
  final pending = List.of(downloads.live);
  for (final item in pending) {
    await downloads.cancel(item);
  }
  if (!context.mounted) return;
  await session.logout();
}
