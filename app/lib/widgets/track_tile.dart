import 'package:flutter/material.dart';

import '../api/detox_api.dart';
import '../app_services.dart';
import 'cover.dart';
import 'equalizer_icon.dart';

enum _TrackAction { next, queue, playlist }

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.services,
    required this.track,
    required this.onTap,
    this.showFolder = true,
  });

  final Services services;
  final Track track;
  final VoidCallback onTap;
  final bool showFolder;

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
        messenger.showSnackBar(
          const SnackBar(content: Text('Плейлисты появятся позже')),
        );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.player,
    builder: (context, _) {
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
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _TrackAction.next,
                  child: Text('Играть следующим'),
                ),
                PopupMenuItem(
                  value: _TrackAction.queue,
                  child: Text('Добавить в очередь'),
                ),
                PopupMenuItem(
                  value: _TrackAction.playlist,
                  child: Text('Добавить в плейлист'),
                ),
              ],
            ),
          ],
        ),
        onTap: onTap,
      );
    },
  );
}
