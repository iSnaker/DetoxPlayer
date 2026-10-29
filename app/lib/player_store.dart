import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Loop mode is stored as a name so the store does not depend on the player.
class SavedPlayback {
  SavedPlayback({
    required this.serverUrl,
    required this.trackIds,
    required this.index,
    required this.positionMs,
    required this.shuffle,
    required this.loop,
  });

  final String serverUrl;

  /// Queue in play order.
  final List<String> trackIds;
  final int index;
  final int positionMs;
  final bool shuffle;
  final String loop;
}

/// Keeps the queue and position between launches. No secrets are stored here.
/// The queue changes rarely and is large, the position changes constantly, so
/// they are written separately.
class PlayerStore {
  static const _queueKey = 'playback_queue_v2';
  static const _stateKey = 'playback_state_v2';
  static const _legacyKey = 'playback_state_v1';

  Future<SavedPlayback?> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyKey);
    final ids = prefs.getStringList(_queueKey);
    final raw = prefs.getString(_stateKey);
    if (ids == null || raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final index = data['index'] as int;
      if (ids.isEmpty || index < 0 || index >= ids.length) return null;
      return SavedPlayback(
        serverUrl: data['server'] as String,
        trackIds: ids,
        index: index,
        positionMs: data['position_ms'] as int,
        shuffle: data['shuffle'] as bool,
        loop: data['loop'] as String,
      );
    } on Object {
      return null;
    }
  }

  Future<void> saveQueue(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_queueKey, ids);
  }

  Future<void> saveState({
    required String serverUrl,
    required int index,
    required int positionMs,
    required bool shuffle,
    required String loop,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _stateKey,
      jsonEncode({
        'server': serverUrl,
        'index': index,
        'position_ms': positionMs,
        'shuffle': shuffle,
        'loop': loop,
      }),
    );
  }
}
