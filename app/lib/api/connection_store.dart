import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Connection {
  Connection(this.url, this.key);

  final String url;
  final String key;
}

class ConnectionStore {
  static const _urlKey = 'server_url';
  static const _keyKey = 'device_key';
  final _storage = const FlutterSecureStorage();

  Future<Connection?> load() async {
    final url = await _storage.read(key: _urlKey);
    final key = await _storage.read(key: _keyKey);
    if (url == null || key == null) return null;
    return Connection(url, key);
  }

  Future<void> save(Connection connection) async {
    await _storage.write(key: _urlKey, value: connection.url);
    await _storage.write(key: _keyKey, value: connection.key);
  }

  Future<String?> lastUrl() => _storage.read(key: _urlKey);

  Future<void> clearKey() => _storage.delete(key: _keyKey);
}
