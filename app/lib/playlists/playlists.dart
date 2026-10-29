import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/detox_api.dart';
import '../storage/json_store.dart';

class Playlist {
  Playlist(this.id, this.name, this.tracks);
  final String id;
  String name;
  final List<Track> tracks;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };
  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    json['id'] as String,
    json['name'] as String,
    (json['tracks'] as List)
        .map((t) => Track.fromJson(Map<String, dynamic>.from(t as Map)))
        .toList(),
  );
}

class Playlists extends ChangeNotifier {
  Playlists(String server, {JsonStore? store})
    : _store = store ?? JsonStore('playlists-${storageId(server)}');
  final JsonStore _store;
  final List<Playlist> _items = [];
  bool _disposed = false;
  String? error;
  late final Future<void> ready = _load();
  List<Playlist> get items => List.unmodifiable(_items);
  Future<void> _load() async {
    try {
      final data = await _store.read();
      _items.addAll(
        (data['items'] as List? ?? []).map(
          (p) => Playlist.fromJson(Map<String, dynamic>.from(p as Map)),
        ),
      );
    } on Object {
      error = 'Не удалось прочитать плейлисты. Данные не перезаписаны.';
    }
    if (!_disposed) notifyListeners();
  }

  String _name(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 100) {
      throw ArgumentError('Название: от 1 до 100 символов');
    }
    return name;
  }

  Future<void> _save() async {
    if (error != null) throw StateError(error!);
    await _store.write({
      'version': 1,
      'items': _items.map((p) => p.toJson()).toList(),
    });
    if (!_disposed) notifyListeners();
  }

  Future<Playlist> create(String name) async {
    await ready;
    final item = Playlist(
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      _name(name),
      [],
    );
    _items.add(item);
    try {
      await _save();
    } on Object {
      _items.remove(item);
      rethrow;
    }
    return item;
  }

  Future<void> rename(Playlist item, String name) async {
    await ready;
    final old = item.name;
    item.name = _name(name);
    try {
      await _save();
    } on Object {
      item.name = old;
      rethrow;
    }
  }

  Future<void> delete(Playlist item) async {
    await ready;
    final index = _items.indexOf(item);
    if (index < 0) return;
    _items.removeAt(index);
    try {
      await _save();
    } on Object {
      _items.insert(index, item);
      rethrow;
    }
  }

  Future<void> add(Playlist item, Iterable<Track> tracks) async {
    await ready;
    final old = List<Track>.of(item.tracks);
    final ids = item.tracks.map((t) => t.id).toSet();
    item.tracks.addAll(tracks.where((t) => ids.add(t.id)));
    try {
      await _save();
    } on Object {
      item.tracks
        ..clear()
        ..addAll(old);
      rethrow;
    }
  }

  Future<void> remove(Playlist item, String trackId) async {
    await ready;
    final old = List<Track>.of(item.tracks);
    item.tracks.removeWhere((t) => t.id == trackId);
    try {
      await _save();
    } on Object {
      item.tracks
        ..clear()
        ..addAll(old);
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
