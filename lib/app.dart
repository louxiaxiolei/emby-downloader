import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'downloads/download_service.dart';
import 'session_controller.dart';
import 'storage/settings_store.dart';
import 'theme.dart';
import 'ui/login_page.dart';
import 'ui/messenger.dart';
import 'ui/shell_page.dart';

class EmbyApp extends StatelessWidget {
  const EmbyApp({
    super.key,
    required this.session,
    required this.downloads,
    required this.settings,
  });

  final SessionController session;
  final DownloadService downloads;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: session),
        ChangeNotifierProvider<DownloadService>.value(value: downloads),
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ],
      child: Builder(
        builder: (context) {
          return MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        title: 'Emby 下载',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: context.watch<SettingsStore>().themeMode,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Gate(),
      );
        },
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final signedIn = context.watch<SessionController>().signedIn;
    return signedIn ? const ShellPage() : const LoginPage();
  }
}
