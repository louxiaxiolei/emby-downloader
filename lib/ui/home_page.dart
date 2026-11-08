import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import '../emby/api.dart';
import '../emby/models.dart';
import '../emby/urls.dart';
import '../session_controller.dart';
import '../theme.dart';
import 'browse_page.dart';
import 'chrome.dart';
import 'detail_page.dart';
import 'widgets.dart';

class LibraryShelf {
  const LibraryShelf({required this.title, required this.parentId, required this.items});

  final String title;
  final String parentId;
  final List<EmbyItem> items;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _loading = true;
  String? _error;
  List<EmbyItem> _hero = const [];
  List<EmbyItem> _resume = const [];
  List<EmbyItem> _nextUp = const [];
  List<LibraryShelf> _shelves = const [];
  Color? _tint;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = context.read<SessionController>().client;
    if (client == null) return;
    setState(() {
      _loading = _hero.isEmpty;
      _error = null;
    });
    try {
      final featured = await client.featured();
      final resume = await _quiet(client.resumeItems);
      final next = await _quiet(client.nextUp);
      final views = await client.views();
      final shelves = <LibraryShelf>[];
      for (final view in views.items) {
        if (view.collectionType == 'photos' || view.collectionType == 'livetv') continue;
        final latest = await _quiet(() => client.latest(parentId: view.id));
        if (latest.isEmpty) continue;
        shelves.add(
          LibraryShelf(title: view.name, parentId: view.id, items: latest),
        );
      }
      if (!mounted) return;
      setState(() {
        _hero = featured;
        _resume = resume;
        _nextUp = next;
        _shelves = shelves;
        _loading = false;
      });
      final first = featured.isEmpty ? null : featured.first;
      if (first != null) {
        _sample(client.imageUrl(first, type: 'Backdrop', maxWidth: 240), client.headers);
      }
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

  Future<List<EmbyItem>> _quiet(Future<List<EmbyItem>> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _sample(String url, Map<String, String> headers) async {
    if (url.isEmpty) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url, headers: headers),
        maximumColorCount: 8,
        size: const Size(64, 36),
      );
      final color = palette.lightVibrantColor?.color ??
          palette.vibrantColor?.color ??
          palette.dominantColor?.color;
      if (color != null && mounted) setState(() => _tint = color);
    } catch (_) {}
  }

  void _open(EmbyItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DetailPage(itemId: item.id, hint: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<SessionController>().client;
    final cinema = context.cinema;
    final tint = _tint ?? (cinema.dark ? const Color(0xFF3A4250) : const Color(0xFFC9D4DE));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tint.withValues(alpha: cinema.dark ? 0.55 : 0.72),
            cinema.background.withValues(alpha: 0.92),
            cinema.background,
          ],
          stops: const [0, 0.42, 1],
        ),
      ),
      child: _loading && _hero.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _hero.isEmpty
          ? LoadError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: HomeView(
                hero: _hero,
                resume: _resume,
                nextUp: _nextUp,
                shelves: _shelves,
                image: (item, {String type = 'Primary', int? maxWidth, int? maxHeight}) {
                  return client?.imageUrl(item, type: type, maxWidth: maxWidth, maxHeight: maxHeight) ?? '';
                },
                headers: client?.headers ?? const {},
                onOpen: _open,
                onHeroChanged: (item) {
                  _sample(
                    client?.imageUrl(item, type: 'Backdrop', maxWidth: 240) ?? '',
                    client?.headers ?? const {},
                  );
                },
                onShelf: (shelf) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BrowsePage(parentId: shelf.parentId, title: shelf.title),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.hero,
    required this.resume,
    required this.nextUp,
    required this.shelves,
    required this.image,
    required this.headers,
    required this.onOpen,
    required this.onHeroChanged,
    required this.onShelf,
  });

  final List<EmbyItem> hero;
  final List<EmbyItem> resume;
  final List<EmbyItem> nextUp;
  final List<LibraryShelf> shelves;
  final String Function(EmbyItem item, {String type, int? maxWidth, int? maxHeight}) image;
  final Map<String, String> headers;
  final ValueChanged<EmbyItem> onOpen;
  final ValueChanged<EmbyItem> onHeroChanged;
  final ValueChanged<LibraryShelf> onShelf;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final _page = PageController();
  var _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cinema = context.cinema;
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        if (widget.hero.isNotEmpty)
          SizedBox(
            height: 430,
            child: PageView.builder(
              controller: _page,
              itemCount: widget.hero.length,
              onPageChanged: (index) {
                setState(() => _index = index);
                widget.onHeroChanged(widget.hero[index]);
              },
              itemBuilder: (context, index) {
                final item = widget.hero[index];
                return GestureDetector(
                  onTap: () => widget.onOpen(item),
                  child: _HeroCard(
                    item: item,
                    backdrop: widget.image(item, type: 'Backdrop', maxWidth: 1280),
                    logo: widget.image(item, type: 'Logo', maxWidth: 800),
                    headers: widget.headers,
                  ),
                );
              },
            ),
          ),
        if (widget.hero.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.hero.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index ? cinema.text : cinema.muted.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ],
            ),
          ),
        if (widget.resume.isNotEmpty)
          _WideShelf(
            title: '继续观看',
            items: widget.resume,
            image: widget.image,
            headers: widget.headers,
            onOpen: widget.onOpen,
            showProgress: true,
          ),
        if (widget.nextUp.isNotEmpty)
          _WideShelf(
            title: '下一集',
            items: widget.nextUp,
            image: widget.image,
            headers: widget.headers,
            onOpen: widget.onOpen,
            showProgress: false,
          ),
        for (final shelf in widget.shelves) ...[
          ShelfHeader(title: '最近更新 · ${shelf.title}', onMore: () => widget.onShelf(shelf)),
          SizedBox(
            height: 168,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: shelf.items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = shelf.items[index];
                final year = item.productionYear?.toString() ?? '';
                final genre = item.genres.isEmpty ? '' : item.genres.first;
                return GestureDetector(
                  onTap: () => widget.onOpen(item),
                  child: SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: EmbyImage(
                              url: widget.image(item, type: 'Backdrop', maxWidth: 640),
                              headers: widget.headers,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          [year, genre].where((part) => part.isNotEmpty).join(' · '),
                          maxLines: 1,
                          style: TextStyle(color: cinema.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (widget.hero.isEmpty && widget.shelves.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: EmptyHint(message: '资料库是空的'),
          ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.item,
    required this.backdrop,
    required this.logo,
    required this.headers,
  });

  final EmbyItem item;
  final String backdrop;
  final String logo;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final places = item.productionLocations.take(2).join('/');
    final genres = item.genres.take(2).join(' ');
    final date = (item.premiereDate ?? '').split('T').first;
    final meta = [places, genres, date].where((part) => part.isNotEmpty).join(' · ');
    return Stack(
      fit: StackFit.expand,
      children: [
        EmbyImage(url: backdrop, headers: headers),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x22000000), Color(0x00000000), Color(0xCC101114)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 88, 24, 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (logo.isNotEmpty)
                SizedBox(
                  height: 84,
                  child: EmbyImage(url: logo, headers: headers, fit: BoxFit.contain),
                )
              else
                Text(
                  item.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w200,
                    letterSpacing: item.name.length <= 6 ? 8 : 1,
                    height: 1.05,
                  ),
                ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(meta, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
              if ((item.overview ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.overview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, height: 1.35, fontSize: 13),
                ),
              ],
              const SizedBox(height: 10),
              _RatingRow(item: item, onDark: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _WideShelf extends StatelessWidget {
  const _WideShelf({
    required this.title,
    required this.items,
    required this.image,
    required this.headers,
    required this.onOpen,
    required this.showProgress,
  });

  final String title;
  final List<EmbyItem> items;
  final String Function(EmbyItem item, {String type, int? maxWidth, int? maxHeight}) image;
  final Map<String, String> headers;
  final ValueChanged<EmbyItem> onOpen;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final cinema = context.cinema;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeader(title: title),
        SizedBox(
          height: 196,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final fraction = item.watchFraction;
              final label = item.type == 'Episode'
                  ? [item.seriesName, episodeCode(item)].whereType<String>().where((p) => p.isNotEmpty).join(' ')
                  : item.name;
              return GestureDetector(
                onTap: () => onOpen(item),
                child: SizedBox(
                  width: 250,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              EmbyImage(
                                url: image(item, type: 'Backdrop', maxWidth: 700),
                                headers: headers,
                              ),
                              if (showProgress && fraction != null)
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  bottom: 8,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        formatSeen(item.playbackPositionTicks),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: fraction,
                                          minHeight: 3,
                                          color: Colors.white,
                                          backgroundColor: Colors.white24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(label.isEmpty ? item.name : label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        timeAgo(item.lastPlayed),
                        style: TextStyle(color: cinema.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class RatingRow extends StatelessWidget {
  const RatingRow({super.key, required this.item, this.onDark = false});

  final EmbyItem item;
  final bool onDark;

  @override
  Widget build(BuildContext context) => _RatingRow(item: item, onDark: onDark);
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.item, required this.onDark});

  final EmbyItem item;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (item.communityRating != null)
        _chip('★ ${item.communityRating!.toStringAsFixed(1)}', const Color(0xFFF5C451), Colors.black),
      if (item.criticRating != null)
        _chip('${item.criticRating!.round()}%', const Color(0xFFE85D4C), Colors.white),
      if (item.officialRating != null && item.officialRating!.isNotEmpty)
        _chip(item.officialRating!, onDark ? Colors.white24 : const Color(0x22000000), onDark ? Colors.white : context.cinema.text),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _chip(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}
