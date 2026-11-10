import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../emby/models.dart';

abstract class SecureBox {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureBox implements SecureBox {
  FlutterSecureBox(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecureBox implements SecureBox {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class SavedAccount {
  const SavedAccount({required this.session, this.needsReauth = false});

  final EmbySession session;
  final bool needsReauth;

  String get id => accountId(session);

  SavedAccount copyWith({EmbySession? session, bool? needsReauth}) {
    return SavedAccount(
      session: session ?? this.session,
      needsReauth: needsReauth ?? this.needsReauth,
    );
  }

  Map<String, dynamic> toJson() => {
    'session': session.toJson(),
    'needsReauth': needsReauth,
  };

  factory SavedAccount.fromJson(Map<String, dynamic> json) {
    return SavedAccount(
      session: EmbySession.fromJson(Map<String, dynamic>.from(json['session'] as Map)),
      needsReauth: json['needsReauth'] as bool? ?? false,
    );
  }
}

String accountId(EmbySession session) => '${session.base}|${session.userId}';

class AccountBook {
  const AccountBook({required this.accounts, this.activeId});

  final List<SavedAccount> accounts;
  final String? activeId;

  SavedAccount? get active {
    for (final account in accounts) {
      if (account.id == activeId) return account;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'activeId': activeId,
    'accounts': [for (final account in accounts) account.toJson()],
  };

  factory AccountBook.fromJson(Map<String, dynamic> json) {
    final raw = json['accounts'];
    return AccountBook(
      activeId: json['activeId'] as String?,
      accounts: [
        if (raw is List)
          for (final entry in raw)
            if (entry is Map) SavedAccount.fromJson(Map<String, dynamic>.from(entry)),
      ],
    );
  }
}

class SessionStore {
  SessionStore({SecureBox? box, FlutterSecureStorage? storage})
    : _box =
          box ??
          FlutterSecureBox(
            storage ??
                const FlutterSecureStorage(
                  aOptions: AndroidOptions(resetOnError: true),
                  iOptions: IOSOptions(
                    accessibility: KeychainAccessibility.first_unlock_this_device,
                    synchronizable: false,
                  ),
                ),
          );

  static const _deviceKey = 'device_id';
  static const _sessionKey = 'session';
  static const _accountsKey = 'accounts';

  final SecureBox _box;

  Future<String> deviceId() async {
    final existing = await _box.read(_deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _box.write(_deviceKey, created);
    return created;
  }

  /// Active session. A legacy single-session record is migrated on read.
  Future<EmbySession?> read() async => (await loadBook()).active?.session;

  Future<AccountBook> loadBook() async {
    final raw = await _box.read(_accountsKey);
    if (raw != null && raw.isNotEmpty) {
      final json = jsonDecode(raw);
      if (json is Map) return AccountBook.fromJson(Map<String, dynamic>.from(json));
    }
    final legacy = await _box.read(_sessionKey);
    if (legacy == null || legacy.isEmpty) return const AccountBook(accounts: []);
    final json = jsonDecode(legacy);
    if (json is! Map) return const AccountBook(accounts: []);
    final session = EmbySession.fromJson(Map<String, dynamic>.from(json));
    final book = AccountBook(accounts: [SavedAccount(session: session)], activeId: accountId(session));
    await _persist(book);
    await _box.delete(_sessionKey);
    return book;
  }

  Future<void> write(EmbySession session) => upsert(session);

  Future<AccountBook> upsert(EmbySession session, {bool makeActive = true}) async {
    final book = await loadBook();
    final id = accountId(session);
    final next = [
      for (final account in book.accounts)
        if (account.id != id) account,
      SavedAccount(session: session),
    ];
    final saved = AccountBook(accounts: next, activeId: makeActive ? id : book.activeId ?? id);
    await _persist(saved);
    return saved;
  }

  Future<AccountBook> setActive(String id) async {
    final book = await loadBook();
    final saved = AccountBook(accounts: book.accounts, activeId: id);
    await _persist(saved);
    return saved;
  }

  Future<AccountBook> markReauth(EmbySession session) async {
    final book = await loadBook();
    final id = accountId(session);
    final saved = AccountBook(
      activeId: book.activeId,
      accounts: [
        for (final account in book.accounts)
          if (account.id == id) account.copyWith(needsReauth: true) else account,
      ],
    );
    await _persist(saved);
    return saved;
  }

  Future<AccountBook> remove(String id) async {
    final book = await loadBook();
    final remaining = [for (final account in book.accounts) if (account.id != id) account];
    final active = book.activeId == id ? (remaining.isEmpty ? null : remaining.first.id) : book.activeId;
    final saved = AccountBook(accounts: remaining, activeId: active);
    await _persist(saved);
    return saved;
  }

  Future<void> clear() async {
    await _box.delete(_accountsKey);
    await _box.delete(_sessionKey);
  }

  Future<void> _persist(AccountBook book) {
    return _box.write(_accountsKey, jsonEncode(book.toJson()));
  }
}
