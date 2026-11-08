import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'downloads/download_service.dart';
import 'session_controller.dart';
import 'storage/session_store.dart';
import 'storage/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final settings = SettingsStore();
  await settings.load();
  final store = SessionStore();
  final downloads = DownloadService(settings);
  await downloads.init();
  String? message;
  final session = SessionController(store: store);
  try {
    final saved = await store.read();
    if (saved != null) {
      final restored = SessionController(store: store, initial: saved);
      await restored.restore();
      runApp(EmbyApp(session: restored, downloads: downloads, settings: settings));
      return;
    }
  } catch (_) {
    message = '无法读取已保存的登录信息，请重新登录';
  }
  session.authMessage = message;
  runApp(EmbyApp(session: session, downloads: downloads, settings: settings));
}
