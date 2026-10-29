import 'package:detox_player/player_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved playback survives a round trip', () async {
    final store = PlayerStore();
    expect(await store.load(), isNull);
    await store.saveQueue(['a', 'b', 'c']);
    await store.saveState(
      serverUrl: 'https://example.org',
      index: 1,
      positionMs: 1500,
      shuffle: true,
      loop: 'all',
    );
    final loaded = (await store.load())!;
    expect(loaded.trackIds, ['a', 'b', 'c']);
    expect(loaded.index, 1);
    expect(loaded.positionMs, 1500);
    expect(loaded.shuffle, isTrue);
    expect(loaded.loop, 'all');
    expect(loaded.serverUrl, 'https://example.org');
  });

  test('a large queue is stored whole', () async {
    final store = PlayerStore();
    final ids = List.generate(5000, (i) => 'id$i');
    await store.saveQueue(ids);
    await store.saveState(
      serverUrl: 's',
      index: 4999,
      positionMs: 0,
      shuffle: false,
      loop: 'off',
    );
    final loaded = (await store.load())!;
    expect(loaded.trackIds.length, 5000);
    expect(loaded.trackIds[loaded.index], 'id4999');
  });

  test('corrupt or inconsistent data is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'playback_queue_v2': ['a'],
      'playback_state_v2': '{bad',
    });
    expect(await PlayerStore().load(), isNull);
    SharedPreferences.setMockInitialValues({
      'playback_queue_v2': ['a'],
      'playback_state_v2': '{"server":"s","index":5,"position_ms":0,"shuffle":false,"loop":"off"}',
    });
    expect(await PlayerStore().load(), isNull);
  });
}
