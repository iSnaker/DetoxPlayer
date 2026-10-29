import '../api/detox_api.dart';

const unknownArtist = 'Неизвестный исполнитель';
const variousArtists = 'Разные исполнители';

class Album {
  Album(this.title, this.folder, this.tracks);

  final String title;
  final String folder;
  final List<Track> tracks;

  Track get cover => tracks.first;

  /// The shared artist of all tracks, or [variousArtists].
  late final String artist = () {
    final names = {for (final t in tracks) t.displayArtist};
    return names.length == 1 ? names.first : variousArtists;
  }();
}

class Artist {
  Artist(this.name, this.albums);

  final String name;
  final List<Album> albums;

  Track get cover => albums.first.cover;
  int get trackCount => albums.fold(0, (sum, a) => sum + a.tracks.length);
}

String _lastSegment(String folder) {
  final parts = folder.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? '' : parts.last;
}

/// Albums are keyed by tag and folder, so two different "Greatest Hits" never
/// merge. A track without an album tag is titled after its folder.
List<Album> buildAlbums(Iterable<Track> tracks) {
  final groups = <String, List<Track>>{};
  for (final track in tracks) {
    final key =
        '${track.sourceId}\u0000${track.album.toLowerCase()}\u0000${track.folder}';
    (groups[key] ??= []).add(track);
  }
  final albums = [
    for (final group in groups.values)
      Album(
        group.first.album.isNotEmpty
            ? group.first.album
            : _lastSegment(group.first.folder).isNotEmpty
            ? _lastSegment(group.first.folder)
            : 'Без альбома',
        group.first.folder,
        group,
      ),
  ];
  albums.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return albums;
}

/// An album appears under every artist that has a track on it.
List<Artist> buildArtists(Iterable<Album> albums) {
  final groups = <String, List<Album>>{};
  final names = <String, String>{};
  for (final album in albums) {
    for (final name in {for (final t in album.tracks) t.displayArtist}) {
      final key = name.toLowerCase();
      names.putIfAbsent(key, () => name);
      (groups[key] ??= []).add(album);
    }
  }
  final artists = [
    for (final entry in groups.entries) Artist(names[entry.key]!, entry.value),
  ];
  artists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return artists;
}
