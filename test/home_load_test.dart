import 'dart:async';
import 'dart:convert';

import 'package:emby_downloader/emby/api.dart';
import 'package:emby_downloader/emby/models.dart';
import 'package:emby_downloader/session_controller.dart';
import 'package:emby_downloader/storage/session_store.dart';
import 'package:emby_downloader/theme.dart';
import 'package:emby_downloader/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('home renders libraries when the hero request hangs and resume fails', (tester) async {
    final hanging = Completer<http.Response>();
    addTearDown(() {
      if (!hanging.isCompleted) {
        hanging.complete(http.Response('{}', 500));
      }
    });
    http.Response jsonResponse(Object body) {
      return http.Response(
        jsonEncode(body),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    }

    final httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/Views')) {
        return jsonResponse({
          'Items': [
            {
              'Name': '电影',
              'Id': 'lib',
              'Type': 'CollectionFolder',
              'CollectionType': 'movies',
            },
          ],
        });
      }
      if (path.contains('/Items/Latest')) {
        return jsonResponse([
          {'Name': '龙猫', 'Id': 'totoro', 'Type': 'Movie', 'ProductionYear': 1988},
        ]);
      }
      if (path.contains('/Items/Resume') || path.contains('/NextUp')) {
        throw Exception('resume down');
      }
      if (path.contains('/Items')) {
        return hanging.future;
      }
      return http.Response('{}', 404);
    });
    final emby = EmbyClient(
      session: const EmbySession(
        base: 'http://192.168.1.10:8096',
        apiPrefix: '/emby',
        serverName: 'Tobey',
        serverId: 'server',
        serverVersion: '4.8.0.0',
        userId: 'user-1',
        username: 'me',
        accessToken: 'secret-token',
        allowBadCertificate: false,
      ),
      deviceId: 'device',
      clientName: 'test',
      httpClient: httpClient,
    );
    final controller = SessionController(store: SessionStore())..bindClient(emby);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ChangeNotifierProvider<SessionController>.value(
          value: controller,
          child: const HomePage(sectionTimeout: Duration(milliseconds: 200)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('最近更新 · 电影'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('重试'), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('龙猫'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    if (!hanging.isCompleted) {
      hanging.complete(http.Response('{"Items":[]}', 200, headers: const {'content-type': 'application/json; charset=utf-8'}));
    }
    await tester.pump();
  });
}
