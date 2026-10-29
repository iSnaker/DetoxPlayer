import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:detox_player/api/detox_api.dart';
import 'package:detox_player/offline/download_backend.dart';
import 'package:detox_player/offline/offline_downloads.dart';
import 'package:detox_player/storage/json_store.dart';

class FakeDownloads implements DownloadBackend {
  final controller = StreamController<DownloadEvent>.broadcast(sync: true);
  final queued = <String>[];
  List<DownloadEvent> saved = [];
  final forgotten = <String>[];
  @override
  Stream<DownloadEvent> get events => controller.stream;
  @override
  Future<void> start() async {}
  @override
  Future<List<DownloadEvent>> records() async => saved;
  @override
  Future<bool> enqueue({
    required String taskId,
    required String url,
    required Map<String, String> headers,
    required String directory,
    required String filename,
  }) async {
    queued.add(taskId);
    return true;
  }

  @override
  Future<void> cancel(String id) async {}
  @override
  Future<bool> pause(String id) async => true;
  @override
  Future<bool> resume(String id) async => true;
  @override
  Future<void> forget(String id) async {
    forgotten.add(id);
  }

  @override
  void dispose() {
    controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DetoxApi api;
  late FakeDownloads backend;
  late OfflineDownloads downloads;
  late JsonStore store;
  final track = Track.fromJson({'id': 'one', 'size': 6, 'title': 'One'});
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('detox-download-test-');
    api = DetoxApi('https://server.local', 'test-secret');
    backend = FakeDownloads();
    store = JsonStore('downloads', directory: directory);
    downloads = OfflineDownloads(
      api,
      backend: backend,
      store: store,
      directory: directory,
    );
    await downloads.ready;
  });
  tearDown(() async {
    await downloads.idle;
    downloads.dispose();
    api.close();
    await directory.delete(recursive: true);
  });
  Future<void> event(String status, {int bytes = 0}) async {
    backend.controller.add(
      DownloadEvent(
        downloads.entry(track.id)!.taskId,
        status,
        expectedBytes: bytes,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await downloads.idle;
  }

  Future<File> partial(List<int> bytes) async {
    final item = downloads.entry(track.id)!;
    return File(
      '${directory.path}/${downloads.relativeDirectory}/${item.taskId}.part',
    ).writeAsBytes(bytes);
  }

  test('duplicate requests enqueue once; partial never playable; complete is verified', () async {
    await downloads.downloadAll([track, track]);
    await downloads.downloadAll([track]);
    expect(backend.queued.length, 1);
    await partial([73, 68, 51, 1, 2, 3]);
    expect(downloads.localUri(track.id), isNull);
    await event('complete');
    expect(downloads.entry(track.id)!.status, 'ready');
    expect(downloads.localUri(track.id)!.scheme, 'file');
    expect(backend.forgotten, isNotEmpty);
    final restored = OfflineDownloads(
      api,
      backend: FakeDownloads(),
      store: store,
      directory: directory,
    );
    await restored.ready;
    expect(restored.localTrack(track.id)!.title, 'One');
    restored.dispose();
  });
  test(
    'truncated and non-MP3 responses do not become offline tracks',
    () async {
      await downloads.downloadAll([track]);
      await partial([73, 68, 51]);
      await event('complete');
      expect(downloads.localUri(track.id), isNull);
      expect(downloads.entry(track.id)!.status, 'failed');
      await downloads.downloadAll([track]);
      await partial([60, 104, 116, 109, 108, 62]);
      await event('complete');
      expect(downloads.localUri(track.id), isNull);
    },
  );
  test('cancel ignores late completion and retry replaces task', () async {
    await downloads.downloadAll([track]);
    final old = downloads.entry(track.id)!.taskId;
    await partial([73, 68, 51, 1, 2, 3]);
    await downloads.cancel(track.id);
    await event('complete');
    expect(downloads.entry(track.id)!.status, 'canceled');
    await downloads.downloadAll([track]);
    expect(downloads.entry(track.id)!.taskId, isNot(old));
    backend.controller.add(DownloadEvent(old, 'complete'));
    await Future<void>.delayed(Duration.zero);
    await downloads.idle;
    expect(downloads.entry(track.id)!.status, 'enqueued');
  });
  test('native completion reconciles after process restart', () async {
    await downloads.downloadAll([track]);
    await partial([73, 68, 51, 1, 2, 3]);
    final id = downloads.entry(track.id)!.taskId;
    downloads.dispose();
    backend = FakeDownloads()
      ..saved = [DownloadEvent(id, 'complete', expectedBytes: 6)];
    downloads = OfflineDownloads(
      api,
      backend: backend,
      store: store,
      directory: directory,
    );
    await downloads.ready;
    expect(downloads.localUri(track.id), isNotNull);
    await downloads.remove(track.id);
    expect(downloads.items, isEmpty);
    expect(
      await Directory('${directory.path}/${downloads.relativeDirectory}')
          .list()
          .length,
      0,
    );
  });
  test('missing downloaded file is not exposed after restart', () async {
    await downloads.downloadAll([track]);
    await partial([73, 68, 51, 1, 2, 3]);
    await event('complete');
    await File.fromUri(downloads.localUri(track.id)!).delete();
    downloads.dispose();
    backend = FakeDownloads();
    downloads = OfflineDownloads(
      api,
      backend: backend,
      store: store,
      directory: directory,
    );
    await downloads.ready;
    expect(downloads.entry(track.id)!.status, 'failed');
    expect(downloads.localUri(track.id), isNull);
  });
}
