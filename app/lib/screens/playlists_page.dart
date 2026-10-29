import 'package:flutter/material.dart';

import '../app_services.dart';
import '../playlists/playlists.dart';
import '../widgets/library_actions.dart';
import '../widgets/track_tile.dart';
import '../widgets/mini_player.dart';

class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key, required this.services});
  final Services services;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Плейлисты'),
      actions: [
        IconButton(
          tooltip: 'Создать плейлист',
          icon: const Icon(Icons.add),
          onPressed: () async {
            final name = await playlistName(context);
            if (name != null && context.mounted) {
              await runAction(context, () async {
                await services.playlists.create(name);
              });
            }
          },
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: services.playlists,
      builder: (context, _) {
        final lists = services.playlists.items;
        if (services.playlists.error != null) {
          return Center(child: Text(services.playlists.error!));
        }
        if (lists.isEmpty) {
          return const Center(
            child: Text('Создайте первый плейлист кнопкой +'),
          );
        }
        return ListView.builder(
          itemCount: lists.length,
          itemBuilder: (context, i) {
            final p = lists[i];
            return ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(p.name),
              subtitle: Text('${p.tracks.length} треков'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PlaylistScreen(services: services, playlist: p),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({
    super.key,
    required this.services,
    required this.playlist,
  });
  final Services services;
  final Playlist playlist;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.playlists,
      services.library,
      services.downloads,
    ]),
    builder: (context, _) {
      final tracks = playlist.tracks
          .map(
            (t) =>
                services.library.byId(t.id) ??
                services.downloads.localTrack(t.id) ??
                t,
          )
          .toList();
      final playable = tracks
          .where(
            (t) =>
                services.library.byId(t.id) != null ||
                services.downloads.localUri(t.id) != null,
          )
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(playlist.name),
          actions: [
            IconButton(
              tooltip: 'Переименовать',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final name = await playlistName(
                  context,
                  initial: playlist.name,
                );
                if (name != null && context.mounted) {
                  await runAction(
                    context,
                    () => services.playlists.rename(playlist, name),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Удалить плейлист',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Удалить плейлист?'),
                    content: const Text(
                      'Скачанные треки останутся на устройстве.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Удалить'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await runAction(context, () async {
                    await services.playlists.delete(playlist);
                    if (context.mounted) Navigator.pop(context);
                  });
                }
              },
            ),
          ],
        ),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: playable.isEmpty
                        ? null
                        : () => services.player.playQueue(playable, 0),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Играть'),
                  ),
                  IconButton(
                    tooltip: 'Перемешать',
                    onPressed: playable.isEmpty
                        ? null
                        : () => services.player.playShuffled(playable),
                    icon: const Icon(Icons.shuffle),
                  ),
                  IconButton(
                    tooltip: 'Скачать плейлист',
                    onPressed: playable.isEmpty
                        ? null
                        : () => runAction(
                            context,
                            () => services.downloads.downloadAll(playable),
                          ),
                    icon: const Icon(Icons.download_outlined),
                  ),
                ],
              ),
            ),
            if (tracks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Добавляйте треки и альбомы через их меню.'),
              ),
            for (var i = 0; i < tracks.length; i++)
              Row(
                children: [
                  Expanded(
                    child: TrackTile(
                      services: services,
                      track: tracks[i],
                      available: playable.any((t) => t.id == tracks[i].id),
                      onTap: () => services.player.playQueue(
                        playable,
                        playable.indexWhere((t) => t.id == tracks[i].id),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Убрать из плейлиста',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => runAction(
                      context,
                      () => services.playlists.remove(playlist, tracks[i].id),
                    ),
                  ),
                ],
              ),
          ],
        ),
        bottomNavigationBar: MiniPlayer(controller: services.player),
      );
    },
  );
}
