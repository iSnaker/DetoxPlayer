import 'package:detox_player/api/detox_api.dart';
import 'package:detox_player/player_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _track(int id) => Track(
  id: '$id',
  title: 'Трек $id',
  artist: '',
  album: 'Как Люди',
  folder: 'a',
  filename: '$id.mp3',
  duration: 10,
  audioUrl: '/api/v1/tracks/$id/audio',
  coverUrl: '/api/v1/tracks/$id/cover',
);

SavedPlayback _state(List<Track> tracks, int index) => SavedPlayback(
  serverUrl: 'https://example.org',
  tracks: tracks,
  index: index,
  positionMs: 1500,
  shuffle: true,
  loop: 'all',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved playback survives a round trip', () async {
    final store = PlayerStore();
    expect(await store.load(), isNull);
    await store.save(_state([_track(1), _track(2)], 1));
    final loaded = (await store.load())!;
    expect(loaded.index, 1);
    expect(loaded.tracks.last.title, 'Трек 2');
    expect(loaded.positionMs, 1500);
    expect(loaded.shuffle, isTrue);
    expect(loaded.loop, 'all');
    expect(loaded.serverUrl, 'https://example.org');
  });

  test('long queues are trimmed around the current track', () async {
    final store = PlayerStore();
    final tracks = List.generate(2000, _track);
    await store.save(_state(tracks, 1000));
    final loaded = (await store.load())!;
    expect(loaded.tracks.length, PlayerStore.maxTracks);
    expect(loaded.tracks[loaded.index].id, '1000');
  });

  test('a trimmed queue near the end keeps the current track', () async {
    final store = PlayerStore();
    await store.save(_state(List.generate(2000, _track), 1999));
    final loaded = (await store.load())!;
    expect(loaded.tracks[loaded.index].id, '1999');
  });

  test('corrupt data is ignored', () async {
    SharedPreferences.setMockInitialValues({'playback_state_v1': '{bad'});
    expect(await PlayerStore().load(), isNull);
  });
}
