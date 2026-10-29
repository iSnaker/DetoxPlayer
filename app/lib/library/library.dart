import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/detox_api.dart';

/// Stores the raw library export between launches.
abstract class LibraryCache {
  Future<String?> read();
  Future<void> write(String data);
}

class FileLibraryCache implements LibraryCache {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}library.cache');
  }

  @override
  Future<String?> read() async {
    try {
      final file = await _file();
      return await file.exists() ? await file.readAsString() : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String data) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(data, flush: true);
    await temp.rename(file.path);
  }
}

class ParsedLibrary {
  ParsedLibrary(this.version, this.tracks);

  final String version;
  final List<Track> tracks;
}

/// Parses `{version, total, items}`; top-level so it can run in an isolate.
ParsedLibrary parseLibrary(String body) {
  final data = jsonDecode(body) as Map<String, dynamic>;
  final tracks = <Track>[];
  for (final item in data['items'] as List) {
    final track = Track.fromJson(item as Map<String, dynamic>);
    track.order = tracks.length;
    tracks.add(track);
  }
  return ParsedLibrary(data['version'] as String, tracks);
}

/// The whole track list held in memory, so search, shuffle and queues never
/// wait for the network. It is refreshed only when the server version changes.
class Library extends ChangeNotifier {
  Library(this.api, {LibraryCache? cache, this.parseInIsolate = true})
    : _cache = cache ?? FileLibraryCache();

  final DetoxApi api;
  final LibraryCache _cache;
  final bool parseInIsolate;
  List<Track> _tracks = const [];
  Map<String, Track> _byId = const {};
  String? version;
  bool syncing = false;
  String? syncError;
  bool unauthorized = false;

  /// Completes once the cached copy (if any) has been loaded.
  late final Future<void> loaded = _loadCache();

  UnmodifiableListView<Track> get tracks => UnmodifiableListView(_tracks);
  Track? byId(String id) => _byId[id];

  Future<ParsedLibrary> _parse(String body) => parseInIsolate
      ? compute(parseLibrary, body)
      : Future(() => parseLibrary(body));

  Future<void> _loadCache() async {
    final raw = await _cache.read();
    if (raw == null) return;
    final split = raw.indexOf('\n');
    if (split < 0 || raw.substring(0, split) != api.baseUri.toString()) return;
    try {
      _apply(await _parse(raw.substring(split + 1)));
    } on Object {
      // A damaged cache is replaced by the next sync.
    }
  }

  void _apply(ParsedLibrary parsed) {
    version = parsed.version;
    _tracks = parsed.tracks;
    _byId = {for (final t in parsed.tracks) t.id: t};
    notifyListeners();
  }

  /// Tracks matching every word of [query] in title, artist, album or path.
  List<Track> search(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return _tracks;
    return _tracks
        .where((t) => words.every(t.haystack.contains))
        .toList(growable: false);
  }

  /// Downloads the library when the server has a different version (or always
  /// with [force]). Returns whether the list changed.
  Future<bool> sync({bool force = false}) async {
    if (syncing) return false;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      await loaded;
      if (!force && version != null) {
        if (await api.libraryVersion() == version) return false;
      }
      final body = await api.libraryExport();
      final parsed = await _parse(body);
      if (parsed.version == version && !force) return false;
      await _cache.write('${api.baseUri}\n$body');
      _apply(parsed);
      return true;
    } on ApiException catch (e) {
      unauthorized = e.unauthorized;
      syncError = e.message;
      return false;
    } on Object {
      syncError = 'Не удалось обновить медиатеку';
      return false;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
