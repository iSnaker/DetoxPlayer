import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

String storageId(String value) => sha256.convert(utf8.encode(value)).toString();

class JsonStore {
  JsonStore(this.name, {this.directory});
  final String name;
  final Directory? directory;
  Future<void> _writes = Future.value();
  Future<File> get file async {
    final dir = directory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/$name.json');
  }

  Future<Map<String, dynamic>> read() async {
    await _writes;
    final target = await file;
    if (!await target.exists()) return {};
    return jsonDecode(await target.readAsString()) as Map<String, dynamic>;
  }

  Future<void> write(Map<String, dynamic> value) {
    final encoded = jsonEncode(value);
    final next = _writes.then((_) async {
      final target = await file;
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(target.path);
    });
    _writes = next.catchError((Object _) {});
    return next;
  }
}
