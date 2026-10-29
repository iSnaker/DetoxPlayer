import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api/detox_api.dart';

class PlayerController extends ChangeNotifier {
  PlayerController(this.api) {
    _init();
  }

  final DetoxApi api;
  final AudioPlayer player = AudioPlayer();
  Track? current;
  String? error;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    player.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace _) {
      error = 'Не удалось воспроизвести трек';
      notifyListeners();
    });
  }

  Future<void> play(Track track) async {
    current = track;
    error = null;
    notifyListeners();
    try {
      await player.setAudioSource(
        AudioSource.uri(
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
        ),
      );
      player.play();
    } on Object {
      error = 'Не удалось воспроизвести трек';
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (player.playing) {
      await player.pause();
    } else {
      player.play();
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
