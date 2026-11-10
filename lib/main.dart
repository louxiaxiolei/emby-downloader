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
  final session = SessionController(store: store);
  try {
    await session.restore();
  } catch (_) {
    session.authMessage = '无法读取已保存的登录信息，请重新登录';
  }
  runApp(EmbyApp(session: session, downloads: downloads, settings: settings));
}
