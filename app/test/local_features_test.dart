import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:detox_player/api/detox_api.dart';
import 'package:detox_player/playlists/playlists.dart';
import 'package:detox_player/storage/json_store.dart';
import 'package:detox_player/diagnostics/diagnostics.dart';
import 'package:detox_player/library/groups.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('detox-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test(
    'playlist CRUD persists snapshots and deduplicates album tracks',
    () async {
      final store = JsonStore('playlists', directory: directory);
      final lists = Playlists('server', store: store);
      final p = await lists.create('  Test  ');
      final a = Track.fromJson({
        'id': 'a',
        'title': 'A',
        'source_id': 'source',
        'size': 20,
      });
      final b = Track.fromJson({'id': 'b', 'title': 'B'});
      await lists.add(p, [a, b, a]);
      await lists.add(p, [a]);
      await lists.rename(p, 'Renamed');
      final restored = Playlists('server', store: store);
      await restored.ready;
      expect(restored.items.single.name, 'Renamed');
      expect(restored.items.single.tracks.map((t) => t.id), ['a', 'b']);
      expect(restored.items.single.tracks.first.size, 20);
      await restored.remove(restored.items.single, 'a');
      expect(restored.items.single.tracks.single.id, 'b');
      await restored.delete(restored.items.single);
      final empty = Playlists('server', store: store);
      await empty.ready;
      expect(empty.items, isEmpty);
      lists.dispose();
      restored.dispose();
      empty.dispose();
    },
  );
  test('corrupt playlist storage is not overwritten', () async {
    final store = JsonStore('bad', directory: directory);
    await (await store.file).writeAsString('broken');
    final lists = Playlists('server', store: store);
    await lists.ready;
    expect(lists.error, isNotNull);
    await expectLater(lists.create('New'), throwsStateError);
    expect(await (await store.file).readAsString(), 'broken');
    lists.dispose();
  });
  test(
    'diagnostics redact credentials and URLs, bound history and persist',
    () async {
      final store = JsonStore('logs', directory: directory);
      final logs = Diagnostics(store: store);
      await logs.ready;
      logs.registerSecret('private-key-value');
      logs.event('failure', {
        'message': 'private-key-value Bearer abc dtp_xyz https://private.local/track?secret=1',
        'Authorization': 'Bearer other',
      });
      final exported = await logs.export();
      for (final secret in [
        'private-key-value',
        'abc',
        'dtp_xyz',
        'private.local',
        'Bearer other',
      ]) {
        expect(exported, isNot(contains(secret)));
      }
      for (var i = 0; i < 900; i++) {
        logs.event('test', {'n': i});
      }
      expect(logs.entries.length, 800);
      await logs.flush();
      logs.dispose();
      final restored = Diagnostics(store: store);
      await restored.ready;
      expect(restored.entries.length, 800);
      expect(restored.entries.first['n'], 899);
      await restored.clear();
      expect(restored.entries, isEmpty);
      restored.dispose();
    },
  );
  test('albums from different sources stay separate', () {
    expect(
      buildAlbums([
        for (final source in ['one', 'two'])
          Track.fromJson({
            'id': source,
            'source_id': source,
            'album': 'Album',
            'folder': 'same',
          }),
      ]).length,
      2,
    );
  });
  test('API refuses audio URL on another origin', () {
    final api = DetoxApi('https://server.local', 'secret');
    expect(
      () => api.resolve('https://other.local/audio'),
      throwsA(isA<ApiException>()),
    );
    api.close();
  });
}
