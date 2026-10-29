import 'library_actions.dart';

import 'package:flutter/material.dart';

import '../api/detox_api.dart';
import '../app_services.dart';
import 'cover.dart';
import 'equalizer_icon.dart';

enum _TrackAction { next, queue, playlist, download, cancel, remove }

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.services,
    required this.track,
    required this.onTap,
    this.showFolder = true,
    this.available = true,
  });

  final Services services;
  final Track track;
  final VoidCallback onTap;
  final bool showFolder;
  final bool available;

  void _onAction(BuildContext context, _TrackAction action) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    switch (action) {
      case _TrackAction.next:
        services.player.playNext([track]);
        messenger.showSnackBar(
          const SnackBar(content: Text('Будет играть следующим')),
        );
      case _TrackAction.queue:
        services.player.addToQueue([track]);
        messenger.showSnackBar(
          const SnackBar(content: Text('Добавлено в очередь')),
        );
      case _TrackAction.playlist:
        addToPlaylist(context, services, [track]);
      case _TrackAction.download:
        runAction(
          context,
          () => services.downloads.downloadAll([track]),
          success: 'Добавлено в загрузки',
        );
      case _TrackAction.cancel:
        runAction(context, () => services.downloads.cancel(track.id));
      case _TrackAction.remove:
        runAction(context, () => services.downloads.remove(track.id));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([services.player, services.downloads]),
    builder: (context, _) {
      final offline = services.downloads.entry(track.id);
      final downloaded = services.downloads.localUri(track.id) != null;
      final active = services.player.current?.id == track.id;
      final scheme = Theme.of(context).colorScheme;
      return ListTile(
        selected: active,
        selectedColor: scheme.onPrimaryContainer,
        selectedTileColor: scheme.primaryContainer,
        leading: Cover(api: services.api, track: track, size: 48),
        title: Text(
          track.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: active ? const TextStyle(fontWeight: FontWeight.w600) : null,
        ),
        subtitle: Text(
          [
            if (!available) 'Нет в медиатеке',
            track.displayArtist,
            if (showFolder && track.folder.isNotEmpty && track.folder != '.')
              track.folder,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (downloaded) const Icon(Icons.offline_pin, size: 18),
            if (offline?.active == true)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (active)
              StreamBuilder<bool>(
                stream: services.player.player.playingStream,
                initialData: services.player.player.playing,
                builder: (context, playing) => EqualizerIcon(
                  playing: playing.data ?? false,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            PopupMenuButton<_TrackAction>(
              tooltip: 'Действия',
              onSelected: (action) => _onAction(context, action),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _TrackAction.next,
                  child: Text('Играть следующим'),
                ),
                const PopupMenuItem(
                  value: _TrackAction.queue,
                  child: Text('Добавить в очередь'),
                ),
                const PopupMenuItem(
                  value: _TrackAction.playlist,
                  child: Text('Добавить в плейлист'),
                ),
                if (downloaded)
                  const PopupMenuItem(
                    value: _TrackAction.remove,
                    child: Text('Удалить скачанный файл'),
                  )
                else if (offline?.active == true || offline?.status == 'paused')
                  const PopupMenuItem(
                    value: _TrackAction.cancel,
                    child: Text('Отменить загрузку'),
                  )
                else
                  const PopupMenuItem(
                    value: _TrackAction.download,
                    child: Text('Скачать для офлайн'),
                  ),
              ],
            ),
          ],
        ),
        onTap: available ? onTap : null,
        enabled: available,
      );
    },
  );
}
