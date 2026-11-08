import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../emby/api.dart';
import '../emby/models.dart';
import '../emby/urls.dart';
import '../session_controller.dart';
import '../theme.dart';
import 'browse_page.dart';
import 'shell_page.dart';
import 'widgets.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  var _loading = true;
  String? _error;
  List<EmbyItem> _items = const [];

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
      final page = await client.views();
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } on EmbyUnauthorized {
      if (!mounted) return;
      await context.read<SessionController>().invalidate();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>().session;
    final client = context.watch<SessionController>().client;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('资料库'),
            if (session != null)
              Text(
                '${session.serverName} · ${session.username}',
                style: const TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w400),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '退出登录',
            onPressed: () => confirmLogout(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _body(client),
    );
  }

  Widget _body(EmbyClient? client) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return LoadError(message: _error!, onRetry: _load);
    if (_items.isEmpty || client == null) {
      return const EmptyHint(message: '这个账号还没有资料库', icon: Icons.video_library_outlined);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 3 : 2;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.35,
            ),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              final image = client.imageUrl(item, type: 'Backdrop', maxWidth: 800);
              final primary = image.isEmpty
                  ? client.imageUrl(item, maxHeight: 400)
                  : image;
              return _LibraryTile(
                item: item,
                imageUrl: primary,
                headers: client.headers,
              );
            },
          );
        },
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.item,
    required this.imageUrl,
    required this.headers,
  });

  final EmbyItem item;
  final String imageUrl;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: panel,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BrowsePage(parentId: item.id, title: item.name),
            ),
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                httpHeaders: headers,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => const ColoredBox(color: panelHigh),
              )
            else
              const ColoredBox(color: panelHigh),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xE60C0D10)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    collectionLabel(item.collectionType),
                    style: const TextStyle(color: brass, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
