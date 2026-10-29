import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

class DownloadEvent {
  const DownloadEvent(
    this.taskId,
    this.status, {
    this.progress = 0,
    this.expectedBytes = 0,
    this.httpStatus,
    this.reason,
  });
  final String taskId, status;
  final double progress;
  final int expectedBytes;
  final int? httpStatus;
  final String? reason;
}

abstract class DownloadBackend {
  Stream<DownloadEvent> get events;
  Future<void> start();
  Future<List<DownloadEvent>> records();
  Future<bool> enqueue({
    required String taskId,
    required String url,
    required Map<String, String> headers,
    required String directory,
    required String filename,
  });
  Future<void> cancel(String id);
  Future<bool> pause(String id);
  Future<bool> resume(String id);
  Future<void> forget(String id);
  void dispose();
}

class NativeDownloadBackend implements DownloadBackend {
  NativeDownloadBackend(this.group);
  final String group;
  final _downloader = FileDownloader();
  final _events = StreamController<DownloadEvent>.broadcast();
  @override
  Stream<DownloadEvent> get events => _events.stream;
  @override
  Future<void> start() async {
    _downloader.registerCallbacks(
      group: group,
      taskStatusCallback: (update) {
        if (_events.isClosed) return;
        final exception = update.exception;
        _events.add(
          DownloadEvent(
            update.task.taskId,
            update.status.name,
            httpStatus: exception is TaskHttpException
                ? exception.httpResponseCode
                : update.responseStatusCode,
            reason: exception?.description,
          ),
        );
      },
      taskProgressCallback: (update) {
        if (_events.isClosed) return;
        _events.add(
          DownloadEvent(
            update.task.taskId,
            'progress',
            progress: update.progress,
            expectedBytes: update.expectedFileSize,
          ),
        );
      },
    );
    await _downloader.configure(
      globalConfig: [
        (Config.checkAvailableSpace, 100),
        (Config.holdingQueue, (2, 2, 2)),
      ],
      iOSConfig: (Config.excludeFromCloudBackup, true),
    );
    _downloader.configureNotificationForGroup(
      group,
      running: const TaskNotification(
        'Detox Player',
        'Скачивание музыки: {progress}%',
      ),
      complete: const TaskNotification('Detox Player', 'Загрузка завершена'),
      error: const TaskNotification('Detox Player', 'Не удалось скачать трек'),
      progressBar: true,
    );
    await _downloader.start(markDownloadedComplete: false);
  }

  @override
  Future<List<DownloadEvent>> records() async =>
      (await _downloader.database.allRecords(group: group))
          .map(
            (r) => DownloadEvent(
              r.taskId,
              r.status.name,
              progress: r.progress,
              expectedBytes: r.expectedFileSize,
              reason: r.exception?.description,
              httpStatus: r.exception is TaskHttpException
                  ? (r.exception as TaskHttpException).httpResponseCode
                  : null,
            ),
          )
          .toList();
  @override
  Future<bool> enqueue({
    required String taskId,
    required String url,
    required Map<String, String> headers,
    required String directory,
    required String filename,
  }) => _downloader.enqueue(
    DownloadTask(
      taskId: taskId,
      url: url,
      headers: headers,
      baseDirectory: BaseDirectory.applicationSupport,
      directory: directory,
      filename: filename,
      group: group,
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
      stallTimeout: const Duration(seconds: 45),
    ),
  );
  Future<DownloadTask?> _task(String id) async =>
      (await _downloader.database.recordForId(id))?.task as DownloadTask?;
  @override
  Future<void> cancel(String id) async {
    await _downloader.cancelTaskWithId(id);
  }

  @override
  Future<bool> pause(String id) async {
    final task = await _task(id);
    return task != null && await _downloader.pause(task);
  }

  @override
  Future<bool> resume(String id) async {
    final task = await _task(id);
    return task != null && await _downloader.resume(task);
  }

  @override
  Future<void> forget(String id) => _downloader.database.deleteRecordWithId(id);
  @override
  void dispose() {
    _downloader.unregisterCallbacks(group: group);
    _events.close();
  }
}
