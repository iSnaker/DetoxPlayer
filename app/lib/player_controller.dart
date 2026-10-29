import 'offline/offline_downloads.dart';
import 'diagnostics/diagnostics.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api/detox_api.dart';
import 'library/library.dart';
import 'player_store.dart';

/// Owns the play queue (the whole list, in play order) and feeds the audio
/// player only a small window of it around the current track. Shuffle and
/// repeat-all are done here, over the full queue, not by the player.
class PlayerController extends ChangeNotifier {
  PlayerController(
    this.api,
    this.library, {
    PlayerStore? store,
    this.downloads,
    AudioPlayer? audioPlayer,
    Future<void> Function()? configureSession,
  }) : _store = store ?? PlayerStore(),
       player = audioPlayer ?? AudioPlayer(),
       _configureSession = configureSession ?? _musicSession {
    ready = _init().catchError(
      (Object e, StackTrace st) => _onPlaybackError(e, st),
    );
  }
  late final Future<void> ready;
  final Future<void> Function() _configureSession;
  static Future<void> _musicSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  final OfflineDownloads? downloads;
  static const _ahead = 5;
  static const _behind = 3;

  final DetoxApi api;
  final Library library;
  final PlayerStore _store;
  final AudioPlayer player;
  final List<Track> _queue = [];
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final _random = Random();
  Timer? _saveTimer;
  Timer? _bufferTimer;
  Set<String> _localIds = {};
  Future<void> _ops = Future.value();
  int _index = 0;
  int _windowStart = 0;
  int _windowCount = 0;
  int _epoch = 0;
  int _restoreToken = 0;

  bool _shuffle = false;
  LoopMode _loop = LoopMode.off;
  bool _disposed = false;
  bool _restoring = false;
  bool _busy = false;
  String? error;

  UnmodifiableListView<Track> get queue => UnmodifiableListView(_queue);
  List<Track> get upcomingQueue => List.unmodifiable(_queue.skip(_index));
  int get index => _index;
  bool get shuffle => _shuffle;
  LoopMode get loop => _loop;
  Track? get current =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;

  Future<void> _init() async {
    await _configureSession();
    if (_disposed) return;
    downloads?.addListener(_downloadsChanged);
    _subscriptions.addAll([
      player.playbackEventStream.listen((_) {}, onError: _onPlaybackError),
      player.currentIndexStream.listen(_onWindowIndex),
      player.playerStateStream.listen((state) {
        Diagnostics.instance.event('player.state', {
          'track': current?.id,
          'state': state.processingState.name,
          'playing': state.playing,
          'positionMs': player.position.inMilliseconds,
          'bufferedMs': player.bufferedPosition.inMilliseconds,
          'window': player.sequence.length,
        });
        _bufferTimer?.cancel();
        if (state.playing &&
            (state.processingState == ProcessingState.loading ||
                state.processingState == ProcessingState.buffering)) {
          _bufferTimer = Timer(const Duration(seconds: 25), () {
            _onPlaybackError(
              TimeoutException('Buffering exceeded 25 seconds'),
              StackTrace.current,
            );
          });
        }
        if (!state.playing) _save();
        if (state.processingState == ProcessingState.completed &&
            _loop == LoopMode.all &&
            !_restoring &&
            _queue.isNotEmpty &&
            _index >= _queue.length - 1) {
          _goTo(0, play: true);
        }
      }),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (player.playing) _save();
    });
    await _restore();
  }

  void _downloadsChanged() {
    final ids = downloads!.items
        .where((e) => e.status == 'ready')
        .map((e) => e.track.id)
        .toSet();
    if (setEquals(ids, _localIds)) return;
    _localIds = ids;
    if (!_disposed && !_restoring && !_busy && _queue.isNotEmpty) {
      unawaited(_resetWindow());
    }
  }

  void _onWindowIndex(int? i) {
    if (_restoring || _busy || i == null) return;
    final queueIndex = _windowStart + i;
    if (queueIndex == _index || queueIndex >= _queue.length) return;
    _index = queueIndex;
    notifyListeners();
    _save();
    _enqueue(_appendAhead);
  }

  AudioSource _source(Track track) => AudioSource.uri(
    downloads?.localUri(track.id) ?? api.resolve(track.audioUrl),
    headers: downloads?.localUri(track.id) == null ? api.headers : null,
    tag: MediaItem(
      id: track.id,
      title: track.displayTitle,
      artist: track.displayArtist,
      album: track.album.isNotEmpty ? track.album : null,
      duration: track.duration == null
          ? null
          : Duration(milliseconds: (track.duration! * 1000).round()),
      artUri: api.resolve(track.coverUrl),
      artHeaders: api.headers,
    ),
  );

  /// Window operations run one at a time; stale ones are dropped.
  Future<void> _enqueue(Future<void> Function() task) {
    final epoch = _epoch;
    return _ops = _ops.then((_) async {
      if (epoch != _epoch || _disposed) return;
      try {
        await task();
      } on Object catch (e, st) {
        _onPlaybackError(e, st);
      }
    });
  }

  Future<void> _appendAhead() async {
    final trim = max(0, _index - _windowStart - _behind);
    if (trim > 0) {
      _busy = true;
      try {
        await player.removeAudioSourceRange(0, trim);
        _windowStart += trim;
        _windowCount -= trim;
      } finally {
        _busy = false;
      }
    }
    final end = min(_queue.length, _index + _ahead + 1);
    final have = _windowStart + _windowCount;
    if (end <= have) return;
    final items = _queue.sublist(have, end);
    _windowCount += items.length;
    try {
      await player.addAudioSources(items.map(_source).toList());
    } on Object {
      _windowCount -= items.length;
      rethrow;
    }
  }

  /// Replaces the player's sources with a window around [index].
  Future<bool> _loadWindow(int index, {Duration? position}) async {
    final epoch = ++_epoch;
    await _ops;
    if (epoch != _epoch || _disposed) return false;
    final start = max(0, index - _behind);
    final end = min(_queue.length, index + _ahead + 1);
    _windowStart = start;
    _windowCount = end - start;
    _index = index;
    Diagnostics.instance.event('player.load', {
      'track': current?.id,
      'index': index,
      'local': current != null && downloads?.localUri(current!.id) != null,
    });
    _busy = true;
    try {
      await player.setAudioSources(
        _queue.sublist(start, end).map(_source).toList(),
        initialIndex: index - start,
        initialPosition: position,
      );
      return epoch == _epoch && !_disposed;
    } finally {
      if (epoch == _epoch) _busy = false;
    }
  }

  /// Keeps the playing source and rebuilds everything around it, so changing
  /// the queue order does not interrupt the current track.
  Future<void> _resetWindow() => _enqueue(() async {
    final k = player.currentIndex;
    if (k == null) return;
    _busy = true;
    try {
      final count = player.sequence.length;
      if (k + 1 < count) await player.removeAudioSourceRange(k + 1, count);
      if (k > 0) await player.removeAudioSourceRange(0, k);
      _windowStart = _index;
      _windowCount = 1;
    } finally {
      _busy = false;
    }
    await _appendAhead();
  });

  void _userAction() {
    _restoreToken++;
    _restoring = false;
  }

  Future<void> _restore() async {
    final token = _restoreToken;
    await library.loaded;
    await downloads?.ready;
    final saved = await _store.load();
    if (saved == null ||
        saved.serverUrl != api.baseUri.toString() ||
        token != _restoreToken ||
        _disposed) {
      return;
    }
    final tracks = <Track>[];
    var index = 0;
    var currentSurvived = false;
    for (var i = 0; i < saved.trackIds.length; i++) {
      final track =
          library.byId(saved.trackIds[i]) ??
          downloads?.localTrack(saved.trackIds[i]);
      if (track == null) continue;
      if (i < saved.index) index = tracks.length + 1;
      if (i == saved.index) {
        index = tracks.length;
        currentSurvived = true;
      }
      tracks.add(track);
    }
    if (tracks.isEmpty) return;
    index = index.clamp(0, tracks.length - 1);
    _queue
      ..clear()
      ..addAll(tracks);
    _shuffle = saved.shuffle;
    _loop = LoopMode.values.asNameMap()[saved.loop] ?? LoopMode.off;
    _index = index;
    _restoring = true;
    notifyListeners();
    try {
      await player.setLoopMode(
        _loop == LoopMode.one ? LoopMode.one : LoopMode.off,
      );
      await _loadWindow(
        index,
        position: currentSurvived
            ? Duration(milliseconds: saved.positionMs)
            : null,
      );
    } on Object {
      // A failed restore must not block normal playback.
    } finally {
      if (token == _restoreToken) _restoring = false;
    }
  }

  void _saveQueue() {
    if (_disposed) return;
    _store.saveQueue([for (final t in _queue) t.id]);
  }

  void _save() {
    if (_disposed || _restoring || current == null) return;
    _store.saveState(
      serverUrl: api.baseUri.toString(),
      index: _index,
      positionMs: player.position.inMilliseconds,
      shuffle: _shuffle,
      loop: _loop.name,
    );
  }

  void _onPlaybackError(Object exception, StackTrace stack) {
    if (_disposed || exception is PlayerInterruptedException) return;
    Diagnostics.instance.event('player.error', {
      'track': current?.id,
      'code': exception is PlayerException ? exception.code : null,
      'sourceIndex': exception is PlayerException ? exception.index : null,
      'message': exception,
      'stack': stack,
      'queueIndex': _index,
      'positionMs': player.position.inMilliseconds,
      'bufferedMs': player.bufferedPosition.inMilliseconds,
      'state': player.processingState.name,
      'local': current != null && downloads?.localUri(current!.id) != null,
    });
    error = 'Ошибка загрузки. Нажмите «Повторить»';
    notifyListeners();
    final track = current;
    if (track != null && downloads?.localUri(track.id) == null && !_probing) {
      _probing = true;
      api.probeAudio(track).whenComplete(() => _probing = false);
    }
  }

  bool _probing = false;
  void _play() => unawaited(
    player.play().catchError(
      (Object e, StackTrace st) => _onPlaybackError(e, st),
    ),
  );

  Future<void> retry() async {
    if (current == null) return;
    _userAction();
    final position = player.position;
    error = null;
    notifyListeners();
    Diagnostics.instance.event('player.retry', {
      'track': current!.id,
      'positionMs': position.inMilliseconds,
    });
    try {
      await player.stop();
      if (await _loadWindow(_index, position: position)) _play();
    } on Object catch (e, st) {
      _onPlaybackError(e, st);
    }
  }

  List<Track> _shuffled(List<Track> tracks, Track first) {
    final rest = tracks.where((t) => t != first).toList()..shuffle(_random);
    return [first, ...rest];
  }

  /// Plays [tracks] starting at [index]. With shuffle on, the whole list is
  /// shuffled and the chosen track plays first.
  Future<void> playQueue(List<Track> tracks, int index) async {
    if (index < 0 || index >= tracks.length) return;
    _userAction();
    final token = _restoreToken;
    await ready;
    if (_disposed || token != _restoreToken) return;
    error = null;
    final chosen = tracks[index];
    _queue
      ..clear()
      ..addAll(_shuffle ? _shuffled(tracks, chosen) : tracks);
    _index = _shuffle ? 0 : index;
    _saveQueue();
    notifyListeners();
    await _start(_index);
  }

  /// Inserts right after the current track; starts playing when nothing is queued.
  Future<void> playNext(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    if (_queue.isEmpty) return playQueue(tracks, 0);
    _queue.insertAll(_index + 1, tracks);
    _saveQueue();
    notifyListeners();
    await _enqueue(() async {
      final k = player.currentIndex;
      if (k == null) return;
      final count = player.sequence.length;
      if (k + 1 < count) await player.removeAudioSourceRange(k + 1, count);
      _windowCount = k + 1;
      await _appendAhead();
    });
  }

  /// Appends to the end of the queue; starts playing when nothing is queued.
  Future<void> addToQueue(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    if (_queue.isEmpty) return playQueue(tracks, 0);
    _queue.addAll(tracks);
    _saveQueue();
    notifyListeners();
    await _enqueue(_appendAhead);
  }

  /// Removes an entry from the queue. The playing track cannot be removed.
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length || index == _index) return;
    _queue.removeAt(index);
    if (index < _index) _index--;
    await _queueChanged(index);
  }

  /// Moves an upcoming track. [to] follows the convention of
  /// `ReorderableListView.onReorder` (the index before the removal shift).
  /// Tracks at or before the playing one are never moved, and nothing can be
  /// dropped in front of the playing track.
  Future<void> moveInQueue(int from, int to) async {
    if (from <= _index || from >= _queue.length) return;
    to = to.clamp(_index + 1, _queue.length - 1);
    if (to == from) return;
    _queue.insert(to, _queue.removeAt(from));
    await _queueChanged(min(from, to));
  }

  /// Persists the queue; the player window is rebuilt only when the change
  /// touches tracks it already holds.
  Future<void> _queueChanged(int firstAffected) async {
    _saveQueue();
    _save();
    notifyListeners();
    if (firstAffected < _windowStart + _windowCount) await _resetWindow();
  }

  Future<void> playShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    _shuffle = true;
    notifyListeners();
    await playQueue(tracks, _random.nextInt(tracks.length));
    _save();
  }

  Future<void> _start(int index) async {
    try {
      if (await _loadWindow(index)) _play();
    } on PlayerInterruptedException {
      // Superseded by a newer request.
    } on Object catch (e, st) {
      _onPlaybackError(e, st);
    }
  }

  Future<void> _goTo(int i, {required bool play}) async {
    if (i < 0 || i >= _queue.length) return;
    _userAction();
    error = null;
    final k = i - _windowStart;
    if (k >= 0 && k < player.sequence.length) {
      await player.seek(Duration.zero, index: k);
      if (play) _play();
    } else {
      _index = i;
      notifyListeners();
      if (play) {
        await _start(i);
      } else {
        try {
          await _loadWindow(i);
        } on Object {
          // The user can retry with play.
        }
      }
    }
  }

  Future<void> jumpTo(int index) => _goTo(index, play: true);

  Future<void> toggle() async {
    if (error != null) return retry();
    if (player.playing) {
      await player.pause();
    } else if (player.sequence.isEmpty && _queue.isNotEmpty) {
      error = null;
      await _start(_index);
    } else {
      _play();
    }
  }

  Future<void> next() async {
    if (_index < _queue.length - 1) {
      await _goTo(_index + 1, play: player.playing);
    } else if (_loop == LoopMode.all) {
      await _goTo(0, play: player.playing);
    }
  }

  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3) || _index == 0) {
      await player.seek(Duration.zero);
    } else {
      await _goTo(_index - 1, play: player.playing);
    }
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    final track = current;
    if (track != null) {
      if (_shuffle) {
        final shuffled = _shuffled(List.of(_queue), track);
        _queue
          ..clear()
          ..addAll(shuffled);
        _index = 0;
      } else {
        _queue.sort((a, b) => a.order.compareTo(b.order));
        _index = _queue.indexOf(track);
      }
      _saveQueue();
    }
    notifyListeners();
    _save();
    if (track != null) await _resetWindow();
  }

  Future<void> cycleLoopMode() async {
    _loop = switch (_loop) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    notifyListeners();
    await player.setLoopMode(
      _loop == LoopMode.one ? LoopMode.one : LoopMode.off,
    );
    _save();
  }

  @override
  void dispose() {
    _save();
    _disposed = true;
    _saveTimer?.cancel();
    _bufferTimer?.cancel();
    downloads?.removeListener(_downloadsChanged);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
