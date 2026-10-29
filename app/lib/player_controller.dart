import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api/detox_api.dart';
import 'player_store.dart';

class PlayerController extends ChangeNotifier {
  PlayerController(this.api, {PlayerStore? store})
    : _store = store ?? PlayerStore() {
    _init();
  }

  static const _maxAutoSkips = 3;

  final DetoxApi api;
  final PlayerStore _store;
  final AudioPlayer player = AudioPlayer();
  final List<Track> _queue = [];
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _saveTimer;
  String? _queueKey;
  int _index = 0;
  int _epoch = 0;
  int _errorStreak = 0;
  bool _disposed = false;
  String? error;

  List<Track> get queue => List.unmodifiable(_queue);
  int get index => _index;
  Track? get current =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _subscriptions.addAll([
      player.playbackEventStream.listen((_) {}, onError: _onPlaybackError),
      player.currentIndexStream.listen((i) {
        if (i == null || i == _index || i >= _queue.length) return;
        _index = i;
        notifyListeners();
        _save();
      }),
      player.shuffleModeEnabledStream.listen((_) => _save()),
      player.loopModeStream.listen((_) => _save()),
      player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.ready) _errorStreak = 0;
        if (!state.playing) _save();
      }),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (player.playing) _save();
    });
    await _restore();
  }

  AudioSource _source(Track track) => AudioSource.uri(
    api.resolve(track.audioUrl),
    headers: api.headers,
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

  Future<void> _restore() async {
    final epoch = _epoch;
    final saved = await _store.load();
    if (saved == null ||
        saved.serverUrl != api.baseUri.toString() ||
        epoch != _epoch ||
        _disposed) {
      return;
    }
    _queue
      ..clear()
      ..addAll(saved.tracks);
    _queueKey = null;
    _index = saved.index;
    notifyListeners();
    try {
      await player.setAudioSources(
        _queue.map(_source).toList(),
        preload: false,
        initialIndex: saved.index,
        initialPosition: Duration(milliseconds: saved.positionMs),
      );
      if (epoch != _epoch || _disposed) return;
      await player.setLoopMode(
        LoopMode.values.asNameMap()[saved.loop] ?? LoopMode.off,
      );
      if (saved.shuffle) {
        await player.shuffle();
        await player.setShuffleModeEnabled(true);
      }
    } on Object {
      // A failed restore must not block normal playback.
    }
  }

  void _save() {
    if (_disposed || current == null) return;
    _store.save(
      SavedPlayback(
        serverUrl: api.baseUri.toString(),
        tracks: List.of(_queue),
        index: _index,
        positionMs: player.position.inMilliseconds,
        shuffle: player.shuffleModeEnabled,
        loop: player.loopMode.name,
      ),
    );
  }

  void _onPlaybackError(Object _, StackTrace stack) {
    error = 'Не удалось воспроизвести трек';
    notifyListeners();
    if (_errorStreak < _maxAutoSkips && player.hasNext) {
      _errorStreak++;
      player.seekToNext();
    }
  }

  /// [key] identifies the list the queue was built from, so that more pages
  /// of the same list can be appended with [extendQueue].
  Future<void> playQueue(List<Track> tracks, int index, {String? key}) async {
    _epoch++;
    _errorStreak = 0;
    _queue
      ..clear()
      ..addAll(tracks);
    _queueKey = key;
    _index = index;
    error = null;
    notifyListeners();
    try {
      await player.setAudioSources(
        _queue.map(_source).toList(),
        initialIndex: index,
      );
      player.play();
    } on PlayerInterruptedException {
      // Superseded by a newer request.
    } on Object {
      error = 'Не удалось воспроизвести трек';
      notifyListeners();
    }
  }

  Future<void> extendQueue(List<Track> tracks, {String? key}) async {
    if (_queue.isEmpty || key != _queueKey || tracks.isEmpty) return;
    _queue.addAll(tracks);
    notifyListeners();
    try {
      await player.addAudioSources(tracks.map(_source).toList());
    } on Object {
      // The queue is extended best-effort; playback of existing items continues.
    }
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _errorStreak = 0;
    error = null;
    await player.seek(Duration.zero, index: index);
    player.play();
  }

  Future<void> toggle() async {
    if (player.playing) {
      await player.pause();
    } else {
      player.play();
    }
  }

  Future<void> next() => player.seekToNext();

  Future<void> previous() => player.seekToPrevious();

  Future<void> toggleShuffle() async {
    final enable = !player.shuffleModeEnabled;
    if (enable) await player.shuffle();
    await player.setShuffleModeEnabled(enable);
  }

  Future<void> cycleLoopMode() => player.setLoopMode(switch (player.loopMode) {
    LoopMode.off => LoopMode.all,
    LoopMode.all => LoopMode.one,
    LoopMode.one => LoopMode.off,
  });

  @override
  void dispose() {
    _save();
    _disposed = true;
    _saveTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
