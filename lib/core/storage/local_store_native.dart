import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<String?> getString(String key) => _preferences.getString(key);

  Future<void> setString(String key, String value) async {
    await _preferences.setString(key, value);
  }

  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }
}
