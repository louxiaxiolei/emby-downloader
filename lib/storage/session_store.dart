import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../emby/models.dart';

class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
            ),
          );

  static const _deviceKey = 'device_id';
  static const _sessionKey = 'session';

  final FlutterSecureStorage _storage;

  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _storage.write(key: _deviceKey, value: created);
    return created;
  }

  Future<EmbySession?> read() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) return null;
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    return EmbySession.fromJson(Map<String, dynamic>.from(json));
  }

  Future<void> write(EmbySession session) {
    return _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));
  }

  Future<void> clear() => _storage.delete(key: _sessionKey);
}
