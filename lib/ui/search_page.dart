import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../emby/api.dart';
import '../emby/models.dart';
import '../emby/urls.dart';
import '../session_controller.dart';
import '../theme.dart';
import 'detail_page.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  var _loading = false;
  String? _error;
  List<EmbyItem> _items = const [];
  var _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _schedule(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String value) async {
    final term = value.trim();
    if (term.isEmpty) {
      setState(() {
        _items = const [];
        _error = null;
        _searched = false;
        _loading = false;
      });
      return;
    }
    final client = context.read<SessionController>().client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final page = await client.search(term);
      if (!mounted || _query.text.trim() != term) return;
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
    final client = context.watch<SessionController>().client;
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: '电影、剧集或单集',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _schedule,
              onSubmitted: _search,
            ),
          ),
          Expanded(child: _results(client)),
        ],
      ),
    );
  }

  Widget _results(client) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return LoadError(message: _error!, onRetry: () => _search(_query.text));
    if (!_searched) return const EmptyHint(message: '搜索你服务器里的电影和剧集', icon: Icons.search);
    if (_items.isEmpty) return const EmptyHint(message: '没有匹配的条目');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
      itemCount: _items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _items[index];
        final code = episodeCode(item);
        final subtitle = [
          switch (item.type) {
            'Movie' => '电影',
            'Series' => '剧集',
            'Episode' => '单集',
            'Video' => '视频',
            _ => item.type,
          },
          if (item.seriesName != null) item.seriesName!,
          if (code != null) code,
          if (item.productionYear != null) '${item.productionYear}',
        ].join(' · ');
        return ListTile(
          leading: Poster(
            url: client?.imageUrl(item, maxHeight: 160) ?? '',
            headers: client?.headers ?? const {},
            width: 42,
            height: 62,
          ),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted)),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => DetailPage(itemId: item.id, hint: item)),
            );
          },
        );
      },
    );
  }
}
