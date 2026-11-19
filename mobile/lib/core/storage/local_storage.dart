/// Local storage — shared preferences wrapper.
library aph_mobile.core.storage;

import 'package:shared_preferences/shared_preferences.dart';

/// Simple key/value local storage.
class LocalStorage {
  LocalStorage._();

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get instance {
    if (_prefs == null) {
      throw StateError('LocalStorage not initialized. Call LocalStorage.init() first.');
    }
    return _prefs!;
  }

  static Future<bool> setString(String key, String value) =>
      instance.setString(key, value);

  static String? getString(String key) => instance.getString(key) as String?;

  static Future<bool> setBool(String key, bool value) => instance.setBool(key, value);

  static bool? getBool(String key) => instance.getBool(key) as bool?;

  static Future<bool> remove(String key) => instance.remove(key);
}
