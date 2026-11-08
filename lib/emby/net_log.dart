import 'package:flutter/foundation.dart';

/// In-app request log. URLs are stored without access tokens.
class NetLog extends ChangeNotifier {
  NetLog._();

  static final instance = NetLog._();

  final List<String> lines = [];

  void add(String line) {
    final clock = DateTime.now().toIso8601String().substring(11, 19);
    lines.add('$clock $line');
    if (lines.length > 300) lines.removeAt(0);
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }

  /// Oldest first, tokens already removed when the line was stored.
  String exportText() => lines.join('\n');

  static String redact(Uri uri) {
    final params = <String, String>{};
    uri.queryParameters.forEach((key, value) {
      final lower = key.toLowerCase();
      if (lower == 'api_key' || lower == 'x-emby-token') return;
      params[key] = value;
    });
    return uri.replace(queryParameters: params.isEmpty ? null : params).toString();
  }
}
