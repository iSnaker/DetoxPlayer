import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:detox_player/api/detox_api.dart';
import 'package:detox_player/library/library.dart';
import 'package:detox_player/player_controller.dart';
import 'package:detox_player/offline/offline_downloads.dart';
import 'package:detox_player/storage/json_store.dart';

import 'offline_downloads_test.dart' show FakeDownloads;
import 'library_test.dart' show MemoryCache;

class FakePlayer extends Fake implements AudioPlayer {
  final indices = StreamController<int?>.broadcast(sync: true);
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  @override
  List<IndexedAudioSource> sequence = [];
  @override
  int? currentIndex;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration bufferedPosition = Duration.zero;
  @override
  ProcessingState processingState = ProcessingState.idle;
  bool failLoad = false;
  int loads = 0, stops = 0, plays = 0;
  @override
  Stream<int?> get currentIndexStream => indices.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    loads++;
    sequence = sources.expand((s) => s.sequence).toList();
    currentIndex = initialIndex ?? 0;
    position = initialPosition ?? Duration.zero;
    if (failLoad) throw PlayerException(7, 'test load failed', 0);
    processingState = ProcessingState.ready;
    indices.add(currentIndex);
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async {
    playing = true;
    plays++;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> stop() async {
    playing = false;
    stops++;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> seek(Duration? value, {int? index}) async {
    position = value ?? Duration.zero;
    if (index != null) {
      currentIndex = index;
      indices.add(index);
    }
  }

  @override
  Future<void> addAudioSources(List<AudioSource> sources) async {
    sequence.addAll(sources.expand((s) => s.sequence));
  }

  @override
  Future<void> removeAudioSourceRange(int start, int end) async {
    sequence.removeRange(start, end);
    if (currentIndex != null && currentIndex! >= end) {
      currentIndex = currentIndex! - (end - start);
      indices.add(currentIndex);
    }
  }

  @override
  Future<void> dispose() async {
    await indices.close();
    await states.close();
    await events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DetoxApi api;
  late Library library;
  late FakePlayer audio;
  late PlayerController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = DetoxApi(
      'https://server.local',
      'secret',
      client: MockClient((_) async => http.Response('', 503)),
    );
    library = Library(api, cache: MemoryCache());
    audio = FakePlayer();
    controller = PlayerController(
      api,
      library,
      audioPlayer: audio,
      configureSession: () async {},
    );
    await controller.ready;
  });
  tearDown(() async {
    controller.dispose();
    library.dispose();
    api.close();
    await Future<void>.delayed(Duration.zero);
  });
  test('queue removal and reordering keep current track intact', () async {
    final tracks = [
      for (var i = 0; i < 10; i++) Track.fromJson({'id': '$i'}),
    ];
    await controller.playQueue(tracks, 3);
    ids() => controller.queue.map((t) => t.id).join(',');
    await controller.removeFromQueue(3);
    expect(ids(), '0,1,2,3,4,5,6,7,8,9');
    await controller.removeFromQueue(0);
    expect(controller.index, 2);
    expect(controller.queue[controller.index].id, '3');
    await controller.removeFromQueue(2);
    expect(controller.queue[controller.index].id, '3');
    await controller.moveInQueue(3, 6);
    expect(controller.queue[6].id, '4');
    await controller.moveInQueue(1, 5);
    expect(controller.queue[1].id, '2');
    expect(controller.queue[controller.index].id, '3');
    final seq = audio.sequence.map((s) => (s.tag as MediaItem).id).toList();
    final window = controller.queue.map((t) => t.id).toList();
    expect(window.join(','), contains(seq.join(',')));
  });
  test('queue view contains only the playing and upcoming tracks', () async {
    final tracks = [
      for (var i = 0; i < 5; i++) Track.fromJson({'id': '$i'}),
    ];
    await controller.playQueue(tracks, 2);

    expect(controller.upcomingQueue.map((track) => track.id), ['2', '3', '4']);

    audio.indices.add(3);

    expect(controller.index, 3);
    expect(controller.upcomingQueue.map((track) => track.id), ['3', '4']);
    expect(controller.queue.map((track) => track.id), [
      '0',
      '1',
      '2',
      '3',
      '4',
    ]);
  });
  test(
    'retry rebuilds failed nonempty sequence and preserves selected position',
    () async {
      audio.failLoad = true;
      await controller.playQueue([
        Track.fromJson({'id': 'a'}),
      ], 0);
      expect(controller.error, isNotNull);
      expect(audio.sequence, isNotEmpty);
      audio.position = const Duration(seconds: 37);
      audio.failLoad = false;
      await controller.toggle();
      expect(audio.loads, 2);
      expect(audio.stops, 1);
      expect(audio.position, const Duration(seconds: 37));
      expect(audio.playing, true);
      expect(controller.error, isNull);
    },
  );
  test(
    'native playback error is recoverable without replacing controller',
    () async {
      await controller.playQueue([
        Track.fromJson({'id': 'a'}),
      ], 0);
      audio.events.addError(
        PlayerException(8, 'network lost', 0),
        StackTrace.current,
      );
      expect(controller.error, isNotNull);
      await controller.retry();
      expect(controller.error, isNull);
      expect(audio.loads, 2);
    },
  );
  test(
    'long queue retains bounded source window and correct global index',
    () async {
      final tracks = [
        for (var i = 0; i < 30; i++) Track.fromJson({'id': '$i'}),
      ];
      await controller.playQueue(tracks, 0);
      for (var i = 1; i < 25; i++) {
        await controller.jumpTo(i);
        await Future<void>.delayed(Duration.zero);
        expect(controller.index, i);
        expect(audio.sequence.length, lessThanOrEqualTo(9));
      }
      expect(controller.queue.length, 30);
    },
  );
  test(
    'offline source is preferred and does not carry authorization headers',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'detox-player-test-',
      );
      final store = JsonStore('download', directory: directory);
      final track = Track.fromJson({'id': 'a', 'size': 6});
      final downloads = OfflineDownloads(
        api,
        backend: FakeDownloads(),
        store: store,
        directory: directory,
      );
      await downloads.ready;
      await store.write({
        'items': [
          {
            'track': track.toJson(),
            'task': 'abcd',
            'status': 'ready',
            'expected': 6,
          },
        ],
      });
      await File('${directory.path}/${downloads.relativeDirectory}/abcd.mp3')
          .writeAsBytes([73, 68, 51, 1, 2, 3]);
      downloads.dispose();
      final restored = OfflineDownloads(
        api,
        backend: FakeDownloads(),
        store: store,
        directory: directory,
      );
      await restored.ready;
      controller.dispose();
      audio = FakePlayer();
      controller = PlayerController(
        api,
        library,
        audioPlayer: audio,
        downloads: restored,
        configureSession: () async {},
      );
      await controller.ready;
      await controller.playQueue([track], 0);
      final source = audio.sequence.single as UriAudioSource;
      expect(source.uri.scheme, 'file');
      expect(source.headers, isNull);
      restored.dispose();
      await directory.delete(recursive: true);
    },
  );
}
