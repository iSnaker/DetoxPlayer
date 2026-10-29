import 'package:detox_player/api/detox_api.dart';
import 'package:detox_player/format.dart';
import 'package:detox_player/library/groups.dart';
import 'package:detox_player/widgets/album_grid.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(
  String id, {
  String album = '',
  String artist = '',
  String folder = 'f',
}) => Track.fromJson({
  'id': id,
  'title': 't$id',
  'artist': artist,
  'album': album,
  'folder': folder,
  'filename': '$id.mp3',
});

void main() {
  test('same album title in different folders stays separate', () {
    final albums = buildAlbums([
      _t('1', album: 'Greatest Hits', artist: 'A', folder: 'A/GH'),
      _t('2', album: 'greatest hits', artist: 'A', folder: 'A/GH'),
      _t('3', album: 'Greatest Hits', artist: 'B', folder: 'B/GH'),
    ]);
    expect(albums.length, 2);
    expect(albums.map((a) => a.tracks.length).toSet(), {1, 2});
  });

  test('a track without album is titled after its folder', () {
    final albums = buildAlbums([_t('1', folder: r'Music\Single Hits')]);
    expect(albums.single.title, 'Single Hits');
    expect(buildAlbums([_t('2', folder: '')]).single.title, 'Без альбома');
  });

  test('album artist is shared or various', () {
    final albums = buildAlbums([
      _t('1', album: 'X', artist: 'A', folder: 'x'),
      _t('2', album: 'X', artist: 'A', folder: 'x'),
      _t('3', album: 'Mix', artist: 'A', folder: 'm'),
      _t('4', album: 'Mix', artist: 'B', folder: 'm'),
    ]);
    expect(albums.firstWhere((a) => a.title == 'X').artist, 'A');
    expect(albums.firstWhere((a) => a.title == 'Mix').artist, variousArtists);
  });

  test('artists list their albums, a compilation appears under each', () {
    final artists = buildArtists(
      buildAlbums([
        _t('1', album: 'X', artist: 'Beta', folder: 'x'),
        _t('2', album: 'Mix', artist: 'Beta', folder: 'm'),
        _t('3', album: 'Mix', artist: 'alpha', folder: 'm'),
        _t('4', album: 'Y', artist: '', folder: 'y'),
      ]),
    );
    expect(artists.map((a) => a.name), ['alpha', 'Beta', unknownArtist]);
    expect(artists[1].albums.length, 2);
    expect(artists[1].trackCount, 3);
  });

  test('grid columns follow the screen width', () {
    expect(albumColumns(360), 2);
    expect(albumColumns(402), 2);
    expect(albumColumns(440), 3);
    expect(albumColumns(768), 4);
    expect(albumColumns(1280), 5);
  });

  test('Russian plurals', () {
    expect(tracksText(1), '1 трек');
    expect(tracksText(3), '3 трека');
    expect(tracksText(5), '5 треков');
    expect(tracksText(11), '11 треков');
    expect(tracksText(21), '21 трек');
    expect(albumsText(12), '12 альбомов');
  });
}
