import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore extends ChangeNotifier {
  bool wifiOnly = false;
  bool publicDownloads = false;
  bool ready = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    wifiOnly = prefs.getBool('wifi_only') ?? false;
    publicDownloads = prefs.getBool('public_downloads') ?? false;
    ready = true;
    notifyListeners();
  }

  Future<void> setWifiOnly(bool value) async {
    wifiOnly = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wifi_only', value);
  }

  Future<void> setPublicDownloads(bool value) async {
    publicDownloads = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('public_downloads', value);
  }
}
