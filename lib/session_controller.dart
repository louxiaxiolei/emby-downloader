import 'dart:io';

import 'package:flutter/foundation.dart';

import 'emby/api.dart';
import 'emby/models.dart';
import 'storage/session_store.dart';

class SessionController extends ChangeNotifier {
  SessionController({required this.store, EmbySession? initial}) : _session = initial;

  final SessionStore store;
  EmbySession? _session;
  EmbyClient? _client;
  String? authMessage;

  EmbySession? get session => _session;
  EmbyClient? get client => _client;
  bool get signedIn => _session != null && _client != null;

  Future<void> restore() async {
    final current = _session;
    if (current == null) return;
    final deviceId = await store.deviceId();
    _client = EmbyClient(
      session: current,
      deviceId: deviceId,
      clientName: embyClientName(),
      httpClient: createHttpClient(allowBadCertificate: current.allowBadCertificate),
      ownsClient: true,
    );
    notifyListeners();
  }

  Future<void> login({
    required String server,
    required String username,
    required String password,
    required bool allowBadCertificate,
  }) async {
    final deviceId = await store.deviceId();
    final httpClient = createHttpClient(allowBadCertificate: allowBadCertificate);
    try {
      final session = await authenticate(
        rawUrl: server,
        username: username,
        password: password,
        deviceId: deviceId,
        clientName: embyClientName(),
        allowBadCertificate: allowBadCertificate,
        httpClient: httpClient,
      );
      _client?.close();
      _session = session;
      _client = EmbyClient(
        session: session,
        deviceId: deviceId,
        clientName: embyClientName(),
        httpClient: httpClient,
        ownsClient: true,
      );
      await store.write(session);
      authMessage = null;
      notifyListeners();
    } catch (error) {
      httpClient.close();
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _client?.logout();
    } catch (_) {}
    _client?.close();
    _client = null;
    _session = null;
    await store.clear();
    notifyListeners();
  }

  Future<void> invalidate() async {
    authMessage = '登录已失效，请重新登录';
    _client?.close();
    _client = null;
    _session = null;
    await store.clear();
    notifyListeners();
  }
}

String embyClientName() {
  if (kIsWeb) return 'Emby下载器';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isAndroid) return 'Android';
  return 'Emby下载器';
}
