import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api/detox_api.dart';

/// Loop mode is stored as a name so the store does not depend on the player.
class SavedPlayback {
  SavedPlayback({
    required this.serverUrl,
    required this.tracks,
    required this.index,
    required this.positionMs,
    required this.shuffle,
    required this.loop,
  });

  final String serverUrl;
  final List<Track> tracks;
  final int index;
  final int positionMs;
  final bool shuffle;
  final String loop;
}

/// Keeps the queue and position between launches. No secrets are stored here.
class PlayerStore {
  static const _key = 'playback_state_v1';
  static const maxTracks = 500;

  Future<SavedPlayback?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final tracks = (data['tracks'] as List)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
      final index = data['index'] as int;
      if (tracks.isEmpty || index < 0 || index >= tracks.length) return null;
      return SavedPlayback(
        serverUrl: data['server'] as String,
        tracks: tracks,
        index: index,
        positionMs: data['position_ms'] as int,
        shuffle: data['shuffle'] as bool,
        loop: data['loop'] as String,
      );
    } on Object {
      return null;
    }
  }

  Future<void> save(SavedPlayback state) async {
    var tracks = state.tracks;
    var index = state.index;
    if (tracks.length > maxTracks) {
      final start = (index - maxTracks ~/ 5).clamp(
        0,
        tracks.length - maxTracks,
      );
      tracks = tracks.sublist(start, start + maxTracks);
      index -= start;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'server': state.serverUrl,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'index': index,
        'position_ms': state.positionMs,
        'shuffle': state.shuffle,
        'loop': state.loop,
      }),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
