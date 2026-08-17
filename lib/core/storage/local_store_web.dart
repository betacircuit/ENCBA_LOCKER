import 'package:web/web.dart' as web;

class LocalStore {
  Future<String?> getString(String key) async =>
      web.window.localStorage.getItem(key);

  Future<void> setString(String key, String value) async {
    web.window.localStorage.setItem(key, value);
  }

  Future<void> remove(String key) async {
    web.window.localStorage.removeItem(key);
  }
}
