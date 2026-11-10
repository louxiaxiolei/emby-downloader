import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../downloads/download_service.dart';
import '../session_controller.dart';
import '../storage/settings_store.dart';
import 'chrome.dart';
import 'downloads_page.dart';
import 'home_page.dart';
import 'log_page.dart';
import 'login_page.dart';
import 'search_page.dart';

class ShellPage extends StatelessWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>().session;
    final active = context.watch<DownloadService>().activeCount;
    return Scaffold(
      body: Stack(
        children: [
          const HomePage(),
          Positioned(
            left: 16,
            bottom: 22,
            child: ServerPill(
              label: session?.serverName ?? '服务器',
              onTap: () => _sheet(context, active),
              onLongPress: () {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LogPage()));
              },
            ),
          ),
          Positioned(
            right: 16,
            bottom: 22,
            child: GlassButton(
              icon: Icons.search,
              tooltip: '搜索',
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage()));
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sheet(BuildContext context, int active) async {
    final settings = context.read<SettingsStore>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Badge(isLabelVisible: active > 0, label: Text('$active'), child: const Icon(Icons.download_rounded)),
                title: const Text('下载'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadsPage()));
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                    ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                  ],
                  selected: {context.watch<SettingsStore>().themeMode},
                  onSelectionChanged: (modes) => settings.setThemeMode(modes.first),
                ),
              ),
              ListenableBuilder(
                listenable: context.read<SessionController>(),
                builder: (context, _) {
                  final accounts = context.read<SessionController>();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final account in accounts.accounts)
                        ListTile(
                          leading: Icon(
                            account.id == accounts.activeAccountId ? Icons.check_circle : Icons.dns_outlined,
                          ),
                          title: Text(account.session.serverName),
                          subtitle: Text(
                            account.needsReauth
                                ? '${account.session.username} · 需要重新登录'
                                : account.session.username,
                          ),
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            if (account.needsReauth) {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => const LoginPage()),
                              );
                              return;
                            }
                            await accounts.switchTo(account.id);
                          },
                        ),
                    ],
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: const Text('添加账号'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('移除当前账号'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  confirmLogout(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> confirmLogout(BuildContext context) async {
  final session = context.read<SessionController>();
  final should = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('移除当前账号'),
      content: const Text('这个账号会从本机移除。已下载的文件、正在进行的下载和录制都会保留。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('移除')),
      ],
    ),
  );
  if (should != true || !context.mounted) return;
  final id = session.activeAccountId;
  if (id == null) return;
  await session.removeAccount(id);
}
