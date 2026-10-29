import 'dart:convert';

import 'package:detox_player/api/detox_api.dart';
import 'package:detox_player/library/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryCache implements LibraryCache {
  String? data;
  int writes = 0;

  @override
  Future<String?> read() async => data;

  @override
  Future<void> write(String value) async {
    data = value;
    writes++;
  }
}

Map<String, dynamic> _item(String id, String title, String artist) => {
  'id': id,
  'title': title,
  'artist': artist,
  'album': '',
  'folder': 'Альбом',
  'filename': '$id.mp3',
  'duration': 10,
};

void main() {
  var version = 'v1';
  var items = [
    _item('1', 'Песня о море', 'Группа Ы'),
    _item('2', 'Другая', 'Исполнитель'),
  ];
  var exports = 0;
  var online = true;

  Library make(MemoryCache cache) {
    final client = MockClient((request) async {
      if (!online) throw http.ClientException('offline');
      final body = request.url.path.endsWith('version')
          ? {'version': version, 'total': items.length}
          : {'version': version, 'total': items.length, 'items': items};
      if (request.url.path.endsWith('export')) exports++;
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });
    return Library(
      DetoxApi('http://x', 'k', client: client),
      cache: cache,
      parseInIsolate: false,
    );
  }

  setUp(() {
    version = 'v1';
    exports = 0;
    online = true;
    items = [
      _item('1', 'Песня о море', 'Группа Ы'),
      _item('2', 'Другая', 'Исполнитель'),
    ];
  });

  test('first sync downloads, caches and indexes the library', () async {
    final cache = MemoryCache();
    final library = make(cache);
    expect(await library.sync(), isTrue);
    expect(library.tracks.length, 2);
    expect(library.byId('2')!.order, 1);
    expect(library.byId('1')!.audioUrl, '/api/v1/tracks/1/audio');
    expect(cache.writes, 1);
  });

  test('search matches every word, ignoring case', () async {
    final library = make(MemoryCache());
    await library.sync();
    expect(library.search('ПЕСНЯ группа').map((t) => t.id), ['1']);
    expect(library.search('  '), hasLength(2));
    expect(library.search('нет такого'), isEmpty);
  });

  test('unchanged version is not downloaded again', () async {
    final cache = MemoryCache();
    await make(cache).sync();
    final second = make(cache);
    expect(await second.sync(), isFalse);
    expect(second.tracks.length, 2);
    expect(exports, 1);
  });

  test('changed version and forced refresh download again', () async {
    final cache = MemoryCache();
    final library = make(cache);
    await library.sync();
    version = 'v2';
    items = [...items, _item('3', 'Новая', 'X')];
    expect(await library.sync(), isTrue);
    expect(library.tracks.length, 3);
    expect(await library.sync(force: true), isTrue);
    expect(exports, 3);
  });

  test('offline keeps the cached copy and reports the error', () async {
    final cache = MemoryCache();
    await make(cache).sync();
    online = false;
    final library = make(cache);
    expect(await library.sync(), isFalse);
    expect(library.tracks.length, 2);
    expect(library.syncError, isNotNull);
  });

  test('cache from another server is ignored', () async {
    final cache = MemoryCache();
    await make(cache).sync();
    cache.data = cache.data!.replaceFirst('http://x', 'http://other');
    online = false;
    final library = make(cache);
    await library.loaded;
    expect(library.tracks, isEmpty);
  });
}
