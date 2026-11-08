import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore extends ChangeNotifier {
  bool wifiOnly = false;
  bool publicDownloads = false;
  bool saveRecordingsToPhotos = false;
  ThemeMode themeMode = ThemeMode.system;
  bool ready = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    wifiOnly = prefs.getBool('wifi_only') ?? false;
    publicDownloads = prefs.getBool('public_downloads') ?? false;
    saveRecordingsToPhotos = prefs.getBool('save_recordings_to_photos') ?? false;
    themeMode = switch (prefs.getString('theme_mode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    ready = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
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

  Future<void> setSaveRecordingsToPhotos(bool value) async {
    saveRecordingsToPhotos = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('save_recordings_to_photos', value);
  }
}
