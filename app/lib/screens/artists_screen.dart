import '../design/brand.dart';

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../format.dart';
import '../library/groups.dart';
import '../widgets/album_grid.dart';
import '../widgets/cover.dart';
import '../widgets/mini_player.dart';
import 'album_screen.dart';

class ArtistsPage extends StatelessWidget {
  const ArtistsPage({super.key, required this.services});

  final Services services;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: libraryAppBar(context, 'Исполнители'),
    body: ListenableBuilder(
      listenable: services.library,
      builder: (context, _) {
        final artists = services.library.artists;
        if (artists.isEmpty) {
          return const Center(child: Text('Медиатека пуста'));
        }
        return ListView.builder(
          itemExtent: 72,
          itemCount: artists.length,
          itemBuilder: (context, i) {
            final artist = artists[i];
            return ListTile(
              leading: Cover(api: services.api, track: artist.cover, size: 48),
              title: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${albumsText(artist.albums.length)} · '
                '${tracksText(artist.trackCount)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ArtistScreen(services: services, artist: artist),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class ArtistScreen extends StatelessWidget {
  const ArtistScreen({super.key, required this.services, required this.artist});

  final Services services;
  final Artist artist;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(artist.name),
      actions: [
        IconButton(
          tooltip: 'Перемешать всё',
          icon: const Icon(Icons.shuffle),
          onPressed: () => services.player.playShuffled([
            for (final album in artist.albums)
              for (final track in album.tracks)
                if (track.displayArtist == artist.name) track,
          ]),
        ),
      ],
    ),
    body: AlbumGrid(
      services: services,
      albums: artist.albums,
      onOpen: (album) => openAlbum(context, services, album),
    ),
    bottomNavigationBar: MiniPlayer(controller: services.player),
  );
}
