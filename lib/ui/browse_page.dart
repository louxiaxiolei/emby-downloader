import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../emby/api.dart';
import '../emby/models.dart';
import '../session_controller.dart';
import '../theme.dart';
import 'detail_page.dart';
import 'season_page.dart';
import 'widgets.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.parentId, required this.title});

  final String parentId;
  final String title;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final _items = <EmbyItem>[];
  final _scroll = ScrollController();
  var _loading = true;
  var _loadingMore = false;
  var _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 480) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore) return;
    if (!reset && _items.length >= _total && _total > 0) return;
    final client = context.read<SessionController>().client;
    if (client == null) return;
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = await client.children(
        parentId: widget.parentId,
        start: reset ? 0 : _items.length,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _total = page.total;
        _loading = false;
        _loadingMore = false;
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
        _loadingMore = false;
      });
    }
  }

  void _open(EmbyItem item) {
    final navigator = Navigator.of(context);
    if (item.type == 'Series') {
      navigator.push(MaterialPageRoute<void>(builder: (_) => DetailPage(itemId: item.id, hint: item)));
      return;
    }
    if (item.type == 'Season' && item.seriesId != null) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => SeasonPage(
            seriesId: item.seriesId!,
            seriesName: item.seriesName ?? '',
            seasonId: item.id,
            seasonName: item.name,
          ),
        ),
      );
      return;
    }
    if (item.canDownload || item.type == 'Movie' || item.type == 'Episode') {
      navigator.push(MaterialPageRoute<void>(builder: (_) => DetailPage(itemId: item.id, hint: item)));
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => BrowsePage(parentId: item.id, title: item.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<SessionController>().client;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
          ? LoadError(message: _error!, onRetry: () => _load(reset: true))
          : _items.isEmpty
          ? const EmptyHint(message: '这里还没有内容')
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1000
                      ? 6
                      : constraints.maxWidth >= 700
                      ? 4
                      : 3;
                  return GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.58,
                    ),
                    itemCount: _items.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _items.length) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final item = _items[index];
                      final year = item.productionYear?.toString() ?? item.seriesName ?? '';
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _open(item),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Poster(
                              url: client?.imageUrl(item, maxHeight: 480) ?? '',
                              headers: client?.headers ?? const {},
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, height: 1.25, fontWeight: FontWeight.w600),
                            ),
                            if (year.isNotEmpty)
                              Text(
                                year,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: muted, fontSize: 11),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}
