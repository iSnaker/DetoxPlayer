import '../widgets/library_actions.dart';

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../format.dart';
import '../library/groups.dart';
import '../widgets/cover.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

void openAlbum(BuildContext context, Services services, Album album) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AlbumScreen(services: services, album: album),
    ),
  );
}

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key, required this.services, required this.album});

  final Services services;
  final Album album;

  @override
  Widget build(BuildContext context) {
    final tracks = album.tracks;
    return Scaffold(
      appBar: AppBar(title: Text(album.title)),
      body: ListView.builder(
        itemCount: tracks.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return _Header(services: services, album: album);
          final track = tracks[i - 1];
          return TrackTile(
            services: services,
            track: track,
            showFolder: false,
            onTap: () => services.player.playQueue(tracks, i - 1),
          );
        },
      ),
      bottomNavigationBar: MiniPlayer(controller: services.player),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.services, required this.album});

  final Services services;
  final Album album;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Cover(
            api: services.api,
            track: album.cover,
            size: 120,
            expand: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                album.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(album.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                tracksText(album.tracks.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                children: [
                  FilledButton.icon(
                    onPressed: () => services.player.playQueue(album.tracks, 0),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Играть'),
                  ),
                  IconButton(
                    tooltip: 'Добавить альбом в плейлист',
                    icon: const Icon(Icons.playlist_add),
                    onPressed: () =>
                        addToPlaylist(context, services, album.tracks),
                  ),
                  IconButton(
                    tooltip: 'Перемешать',
                    icon: const Icon(Icons.shuffle),
                    onPressed: () => services.player.playShuffled(album.tracks),
                  ),
                  ListenableBuilder(
                    listenable: services.downloads,
                    builder: (context, _) {
                      final complete = album.tracks.every(
                        (t) => services.downloads.localUri(t.id) != null,
                      );
                      final loading = album.tracks.any(
                        (t) => services.downloads.entry(t.id)?.active == true,
                      );
                      return IconButton(
                        tooltip: complete
                            ? 'Альбом скачан'
                            : loading
                            ? 'Альбом скачивается'
                            : 'Скачать альбом',
                        icon: Icon(
                          complete
                              ? Icons.offline_pin
                              : loading
                              ? Icons.downloading
                              : Icons.download_outlined,
                        ),
                        onPressed: complete || loading
                            ? null
                            : () => runAction(
                                context,
                                () => services.downloads.downloadAll(
                                  album.tracks,
                                ),
                                success: 'Альбом добавлен в загрузки',
                              ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
