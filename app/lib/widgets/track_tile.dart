import 'package:flutter/material.dart';

import '../api/detox_api.dart';
import '../app_services.dart';
import 'cover.dart';

enum _TrackAction { queue, playlist }

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
  Widget build(BuildContext context) => ListTile(
    leading: Cover(api: services.api, track: track, size: 48),
    title: Text(
      track.displayTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
    trailing: PopupMenuButton<_TrackAction>(
      tooltip: 'Действия',
      onSelected: (action) => _onAction(context, action),
      itemBuilder: (_) => const [
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
    onTap: onTap,
  );
}
