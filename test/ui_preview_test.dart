import 'dart:io';
import 'dart:ui' as ui;

import 'package:emby_downloader/emby/models.dart';
import 'package:emby_downloader/session_controller.dart';
import 'package:emby_downloader/storage/session_store.dart';
import 'package:emby_downloader/theme.dart';
import 'package:emby_downloader/ui/detail_page.dart';
import 'package:emby_downloader/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('save light home and detail previews', (tester) async {
    final fontFile = File('/usr/share/fonts/truetype/wqy/wqy-microhei.ttc');
    if (fontFile.existsSync()) {
      final loader = FontLoader('WenQuanYi')
        ..addFont(Future.value(ByteData.view(fontFile.readAsBytesSync().buffer)));
      await loader.load();
    }
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hero = _movie(
      id: 'prometheus',
      name: '普罗米修斯',
      overview: '一群地球科学家根据古文明壁画的指引，前往遥远的星系进行太空探测。',
      year: 2012,
      date: '2012-05-30',
      places: const ['美国', '英国'],
      genres: const ['科幻', '悬疑'],
      rating: 7.0,
      critic: 73,
    );
    final totoro = _movie(
      id: 'totoro',
      name: '龙猫',
      year: 1988,
      genres: const ['动画'],
      ticks: 6 * 60 * 10000000,
      runtime: 86 * 60 * 10000000,
      played: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: _fontTheme(Brightness.light),
        home: Scaffold(
          body: RepaintBoundary(
            child: HomeView(
              hero: [hero, totoro],
              resume: [totoro],
              nextUp: const [],
              shelves: [
                LibraryShelf(title: '电影', parentId: 'movies', items: [hero, totoro]),
              ],
              image: (item, {String type = 'Primary', int? maxWidth, int? maxHeight}) => '',
              headers: const {},
              onOpen: (_) {},
              onHeroChanged: (_) {},
              onShelf: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _save(tester, '/opt/cursor/artifacts/ui-home.png');

    await tester.pumpWidget(
      MaterialApp(
        theme: _fontTheme(Brightness.light),
        home: ChangeNotifierProvider(
          create: (_) => SessionController(store: SessionStore()),
          child: RepaintBoundary(child: DetailPage(itemId: hero.id, hint: hero)),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('播放'), findsOneWidget);
    await _save(tester, '/opt/cursor/artifacts/ui-detail.png');

    await tester.pumpWidget(
      MaterialApp(
        theme: _fontTheme(Brightness.dark),
        home: Scaffold(
          body: RepaintBoundary(
            child: HomeView(
              hero: [hero],
              resume: [totoro],
              nextUp: const [],
              shelves: [
                LibraryShelf(title: '电影', parentId: 'movies', items: [hero]),
              ],
              image: (item, {String type = 'Primary', int? maxWidth, int? maxHeight}) => '',
              headers: const {},
              onOpen: (_) {},
              onHeroChanged: (_) {},
              onShelf: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _save(tester, '/opt/cursor/artifacts/ui-home-dark.png');
  });
}

ThemeData _fontTheme(Brightness brightness) {
  final base = buildTheme(brightness);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'WenQuanYi'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'WenQuanYi'),
  );
}

EmbyItem _movie({
  required String id,
  required String name,
  String? overview,
  int? year,
  String? date,
  List<String> places = const [],
  List<String> genres = const [],
  double? rating,
  double? critic,
  int? ticks,
  int? runtime,
  DateTime? played,
}) {
  return EmbyItem(
    id: id,
    name: name,
    type: 'Movie',
    overview: overview,
    productionYear: year,
    premiereDate: date,
    productionLocations: places,
    genres: genres,
    communityRating: rating,
    criticRating: critic,
    officialRating: 'PG',
    playbackPositionTicks: ticks,
    runTimeTicks: runtime,
    lastPlayed: played,
  );
}

Future<void> _save(WidgetTester tester, String path) async {
  if (!Directory('/opt/cursor/artifacts').existsSync()) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
