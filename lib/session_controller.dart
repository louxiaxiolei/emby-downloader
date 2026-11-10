import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'emby/api.dart';
import 'emby/models.dart';
import 'storage/session_store.dart';

class SessionController extends ChangeNotifier {
  SessionController({required this.store, EmbySession? initial}) : _session = initial;

  final SessionStore store;
  EmbySession? _session;
  EmbyClient? _client;
  List<SavedAccount> accounts = const [];
  String? authMessage;

  EmbySession? get session => _session;
  EmbyClient? get client => _client;
  String? get activeAccountId => _session == null ? null : accountId(_session!);

  void bindClient(EmbyClient client) {
    _client = client;
    _session = client.session;
    notifyListeners();
  }

  bool get signedIn => _session != null && _client != null;

  Future<void> restore() async {
    final book = await store.loadBook();
    accounts = book.accounts;
    final active = book.active;
    if (active == null || active.needsReauth) {
      _client?.close();
      _client = null;
      _session = active?.session;
      notifyListeners();
      return;
    }
    await _open(active.session);
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
      final book = await store.upsert(session);
      accounts = book.accounts;
      _client?.close();
      await _open(session, httpClient: httpClient);
      authMessage = null;
    } catch (error) {
      httpClient.close();
      rethrow;
    }
  }

  /// Drops one saved account. Downloads already queued keep the token they started with.
  Future<void> removeAccount(String id) async {
    final book = await store.remove(id);
    accounts = book.accounts;
    if (activeAccountId == id) {
      _client?.close();
      _client = null;
      _session = null;
      final next = book.active;
      if (next != null && !next.needsReauth) {
        await _open(next.session);
        return;
      }
      _session = next?.session;
    }
    notifyListeners();
  }

  Future<void> switchTo(String id) async {
    SavedAccount? account;
    for (final candidate in accounts) {
      if (candidate.id == id) account = candidate;
    }
    if (account == null || account.needsReauth) return;
    if (account.id == activeAccountId && _client != null) return;
    _client?.close();
    await store.setActive(id);
    await _open(account.session);
  }

  Future<void> logout() => _session == null ? store.clear() : removeAccount(accountId(_session!));

  /// Only the account that failed is marked. Another saved account becomes active when one exists.
  Future<void> invalidate() async {
    final current = _session;
    if (current != null) {
      final book = await store.markReauth(current);
      accounts = book.accounts;
    }
    _client?.close();
    _client = null;
    SavedAccount? next;
    for (final account in accounts) {
      if (!account.needsReauth) {
        next = account;
        break;
      }
    }
    if (next != null) {
      authMessage = current == null ? '登录已失效' : '「${current.username}」登录已失效，已切换到「${next.session.username}」';
      await store.setActive(next.id);
      await _open(next.session);
      return;
    }
    _session = null;
    authMessage = '登录已失效，请重新登录';
    notifyListeners();
  }

  Future<void> _open(EmbySession session, {http.Client? httpClient}) async {
    final deviceId = await store.deviceId();
    _session = session;
    _client = EmbyClient(
      session: session,
      deviceId: deviceId,
      clientName: embyClientName(),
      httpClient: httpClient ?? createHttpClient(allowBadCertificate: session.allowBadCertificate),
      ownsClient: true,
    );
    notifyListeners();
  }
}

String embyClientName() {
  if (kIsWeb) return 'Emby下载器';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isAndroid) return 'Android';
  return 'Emby下载器';
}
