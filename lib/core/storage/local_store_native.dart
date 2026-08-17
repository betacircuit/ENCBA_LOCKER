import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  Future<String?> getString(String key) => _store.getString(key);

  Future<void> setString(String key, String value) async {
    await _store.setString(key, value);
  }

  Future<void> remove(String key) async {
    await _store.remove(key);
  }
}
