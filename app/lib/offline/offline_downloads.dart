import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/detox_api.dart';
import '../diagnostics/diagnostics.dart';
import '../storage/json_store.dart';
import 'download_backend.dart';

class OfflineTrack {
  OfflineTrack(
    this.track,
    this.taskId, {
    this.status = 'enqueued',
    this.progress = 0,
    this.expectedBytes = 0,
    this.error,
  });
  final Track track;
  final String taskId;
  String status;
  double progress;
  int expectedBytes;
  String? error;
  bool get active => const [
    'enqueued',
    'running',
    'waitingToRetry',
    'verifying',
  ].contains(status);
  Map<String, dynamic> toJson() => {
    'track': track.toJson(),
    'task': taskId,
    'status': status,
    'expected': expectedBytes,
    'error': error,
  };
  factory OfflineTrack.fromJson(Map<String, dynamic> json) => OfflineTrack(
    Track.fromJson(Map<String, dynamic>.from(json['track'] as Map)),
    json['task'] as String,
    status: json['status'] as String,
    expectedBytes: (json['expected'] as num?)?.toInt() ?? 0,
    error: json['error'] as String?,
  );
}

class OfflineDownloads extends ChangeNotifier {
  OfflineDownloads(
    this.api, {
    DownloadBackend? backend,
    JsonStore? store,
    this.directory,
  }) : scope = storageId(api.baseUri.toString()),
       _backend =
           backend ??
           NativeDownloadBackend('music-${storageId(api.baseUri.toString())}'),
       _store =
           store ?? JsonStore('downloads-${storageId(api.baseUri.toString())}');
  final DetoxApi api;
  final String scope;
  final DownloadBackend _backend;
  final JsonStore _store;
  final Directory? directory;
  late Directory _root;
  final Map<String, OfflineTrack> _items = {};
  StreamSubscription<DownloadEvent>? _subscription;
  Future<void> _operations = Future.value();
  bool _disposed = false;
  String? error;
  late final Future<void> ready = _load();
  List<OfflineTrack> get items => List.unmodifiable(_items.values);
  OfflineTrack? entry(String id) => _items[id];
  String get relativeDirectory => 'offline/$scope';
  int get usedBytes => _items.values
      .where((e) => e.status == 'ready')
      .fold(0, (sum, e) => sum + e.expectedBytes);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _serial<T>(Future<T> Function() fn) {
    final next = _operations.then((_) => fn());
    _operations = next.then<void>((_) {}).catchError((Object e) {
      Diagnostics.instance.event('downloads.operation_error', {'message': e});
    });
    return next;
  }

  Future<void> get idle => _operations;
  File _part(OfflineTrack item) => File('${_root.path}/${item.taskId}.part');
  File _final(OfflineTrack item) => File('${_root.path}/${item.taskId}.mp3');
  Future<void> _save() => _store.write({
    'version': 1,
    'items': _items.values.map((e) => e.toJson()).toList(),
  });
  Future<void> _load() async {
    try {
      final base = directory ?? await getApplicationSupportDirectory();
      _root = Directory('${base.path}/$relativeDirectory');
      await _root.create(recursive: true);
      final data = await _store.read();
      for (final raw in data['items'] as List? ?? []) {
        final item = OfflineTrack.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
        if (!RegExp(r'^[a-f0-9]+$').hasMatch(item.taskId)) {
          throw const FormatException('Invalid task ID');
        }
        _items[item.track.id] = item;
        if (item.status == 'ready' &&
            (!await _final(item).exists() ||
                await _final(item).length() != item.expectedBytes)) {
          item.status = 'failed';
          item.error = 'Локальный файл отсутствует или повреждён';
        }
      }
      _subscription = _backend.events.listen((event) {
        unawaited(
          ready.then((_) => _serial(() => _handle(event))).catchError((
            Object e,
          ) {
            error = 'Ошибка сохранения загрузки';
            _changed();
          }),
        );
      });
      await _backend.start();
      final records = await _backend.records();
      for (final record in records) {
        await _handle(record);
      }
      final known = records.map((e) => e.taskId).toSet();
      for (final item in _items.values) {
        if (item.active && !known.contains(item.taskId)) {
          // Completion may have been committed to disk immediately before termination.
          if (await _final(item).exists()) {
            await _complete(item);
          } else {
            item.status = 'failed';
            item.error = 'Загрузка прервана. Нажмите «Повторить»';
          }
        }
      }
      await _save();
    } on Object catch (e) {
      error = 'Не удалось открыть загрузки. Данные сохранены без изменений.';
      Diagnostics.instance.event('downloads.init_error', {'message': e});
    }
    _changed();
  }

  Uri? localUri(String id) {
    final item = _items[id];
    if (item == null || item.status != 'ready') return null;
    final file = _final(item);
    try {
      if (!file.existsSync() || file.lengthSync() != item.expectedBytes) {
        return null;
      }
      return file.uri;
    } on FileSystemException {
      return null;
    }
  }

  Track? localTrack(String id) =>
      localUri(id) != null ? _items[id]?.track : null;
  Future<void> downloadAll(Iterable<Track> tracks) async {
    await ready;
    await _serial(() async {
      if (error != null) throw StateError(error!);
      final added = <OfflineTrack>[];
      for (final track in tracks) {
        final old = _items[track.id];
        if (old != null &&
            (old.active ||
                old.status == 'paused' ||
                localUri(track.id) != null)) {
          continue;
        }
        final id = storageId(
          '$scope/${track.id}/${DateTime.now().microsecondsSinceEpoch}/${Random.secure().nextInt(1 << 32)}',
        );
        final item = OfflineTrack(track, id, expectedBytes: track.size);
        if (old != null) {
          await _backend.cancel(old.taskId);
          await _backend.forget(old.taskId);
          if (await _part(old).exists()) await _part(old).delete();
          if (await _final(old).exists()) await _final(old).delete();
        }
        _items[track.id] = item;
        added.add(item);
      }
      await _save();
      _changed();
      for (final item in added) {
        try {
          final accepted = await _backend.enqueue(
            taskId: item.taskId,
            url: api.resolve(item.track.audioUrl).toString(),
            headers: api.headers,
            directory: relativeDirectory,
            filename: '${item.taskId}.part',
          );
          if (!accepted) throw StateError('enqueue rejected');
          Diagnostics.instance.event('download.enqueued', {
            'track': item.track.id,
            'task': item.taskId,
          });
        } on Object catch (e) {
          item.status = 'failed';
          item.error = 'Не удалось начать загрузку';
          Diagnostics.instance.event('download.enqueue_error', {
            'track': item.track.id,
            'message': e,
          });
        }
      }
      await _save();
      _changed();
    });
  }

  Future<void> _handle(DownloadEvent event) async {
    final matches = _items.values.where((e) => e.taskId == event.taskId);
    if (matches.isEmpty) return;
    final item = matches.first;
    if (item.status == 'ready' || item.status == 'canceled') return;
    if (event.status == 'progress') {
      if (event.progress >= 0) item.progress = event.progress;
      if (event.expectedBytes > 0) item.expectedBytes = event.expectedBytes;
      _changed();
      return;
    }
    if (event.expectedBytes > 0) item.expectedBytes = event.expectedBytes;
    Diagnostics.instance.event('download.status', {
      'track': item.track.id,
      'task': item.taskId,
      'status': event.status,
      'http': event.httpStatus,
      'reason': event.reason,
    });
    item.status = event.status;
    if (event.status == 'complete') {
      await _complete(item);
    } else if (const [
      'failed',
      'notFound',
      'canceled',
    ].contains(event.status)) {
      item.error = switch (event.httpStatus) {
        401 || 403 => 'Ключ недействителен или отозван',
        404 => 'Трек недоступен на сервере',
        _ =>
          event.status == 'canceled'
              ? 'Загрузка отменена'
              : 'Не удалось скачать: проверьте сеть и свободное место',
      };
      // Native task records contain authorization headers; remove terminal records.
      await _backend.forget(item.taskId);
    }
    await _save();
    _changed();
  }

  Future<void> _complete(OfflineTrack item) async {
    item.status = 'verifying';
    _changed();
    final part = _part(item), target = _final(item);
    try {
      final file = await part.exists() ? part : target;
      final size = await file.length();
      if (size <= 0 || item.expectedBytes <= 0 || size != item.expectedBytes) {
        throw const FormatException('Incomplete download');
      }
      final header = await file.open();
      late List<int> bytes;
      try {
        bytes = await header.read(3);
      } finally {
        await header.close();
      }
      if (bytes.length < 3 ||
          !(bytes[0] == 73 && bytes[1] == 68 && bytes[2] == 51 ||
              bytes[0] == 255 && (bytes[1] & 224) == 224)) {
        throw const FormatException('Not MP3');
      }
      if (file.path != target.path) await part.rename(target.path);
      item.status = 'ready';
      item.progress = 1;
      item.error = null;
      Diagnostics.instance.event('download.verified', {
        'track': item.track.id,
        'bytes': size,
      });
    } on Object catch (e) {
      item.status = 'failed';
      item.error = 'Файл не прошёл проверку. Повторите загрузку';
      Diagnostics.instance.event('download.verify_error', {
        'track': item.track.id,
        'message': e,
      });
    }
    await _save();
    await _backend.forget(item.taskId);
  }

  Future<void> cancel(String id) async {
    await ready;
    await _serial(() async {
      final item = _items[id];
      if (item == null || item.status == 'ready') return;
      item.status = 'canceled';
      await _save();
      await _backend.cancel(item.taskId);
      await _backend.forget(item.taskId);
      if (await _part(item).exists()) await _part(item).delete();
      _changed();
    });
  }

  Future<void> pause(String id) async {
    await ready;
    final item = _items[id];
    if (item == null) return;
    if (!await _backend.pause(item.taskId)) {
      throw StateError('Пауза недоступна; можно отменить загрузку');
    }
  }

  Future<void> resume(String id) async {
    await ready;
    final item = _items[id];
    if (item == null) return;
    if (!await _backend.resume(item.taskId)) {
      item.status = 'failed';
      await downloadAll([item.track]);
    }
  }

  Future<void> remove(String id) async {
    await cancel(id);
    await _serial(() async {
      final item = _items.remove(id);
      if (item == null) return;
      if (await _final(item).exists()) await _final(item).delete();
      await _save();
      _changed();
    });
  }

  Future<void> cancelPending() async {
    await ready;
    for (final item in List.of(items)) {
      if (item.active || item.status == 'paused') await cancel(item.track.id);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _backend.dispose();
    super.dispose();
  }
}
