import 'package:flutter/material.dart';

import '../app_services.dart';
import '../widgets/library_actions.dart';
import '../widgets/mini_player.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.services});
  final Services services;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Скачанная музыка')),
    bottomNavigationBar: MiniPlayer(controller: services.player),
    body: ListenableBuilder(
      listenable: services.downloads,
      builder: (context, _) {
        final manager = services.downloads, items = manager.items;
        final playable = items
            .where((e) => manager.localUri(e.track.id) != null)
            .map((e) => e.track)
            .toList();
        return ListView(
          children: [
            ListTile(
              title: Text(
                '${playable.length} треков · ${(manager.usedBytes / 1048576).toStringAsFixed(1)} МБ',
              ),
              subtitle: Text(
                manager.error ??
                    'Хранятся на этом устройстве. Можно слушать без сети.',
              ),
              trailing: IconButton(
                tooltip: 'Играть скачанное',
                icon: const Icon(Icons.play_arrow),
                onPressed: playable.isEmpty
                    ? null
                    : () => services.player.playQueue(playable, 0),
              ),
            ),
            for (final item in items)
              ListTile(
                title: Text(item.track.displayTitle),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.error ??
                          switch (item.status) {
                            'ready' => 'Скачано',
                            'paused' => 'Приостановлено',
                            'running' => 'Скачивание…',
                            'enqueued' => 'В очереди',
                            'waitingToRetry' => 'Ожидание сети…',
                            'verifying' => 'Проверка файла…',
                            _ => 'Загрузка остановлена',
                          },
                    ),
                    if (item.active)
                      LinearProgressIndicator(
                        value: item.progress > 0
                            ? item.progress.clamp(0, 1)
                            : null,
                      ),
                  ],
                ),
                onTap: manager.localUri(item.track.id) == null
                    ? null
                    : () => services.player.playQueue(
                        playable,
                        playable.indexWhere((t) => t.id == item.track.id),
                      ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) => runAction(
                    context,
                    () => switch (action) {
                      'pause' => manager.pause(item.track.id),
                      'resume' => manager.resume(item.track.id),
                      'cancel' => manager.cancel(item.track.id),
                      'retry' => manager.downloadAll([item.track]),
                      _ => manager.remove(item.track.id),
                    },
                  ),
                  itemBuilder: (_) => [
                    if (item.status == 'running')
                      const PopupMenuItem(value: 'pause', child: Text('Пауза')),
                    if (item.status == 'paused')
                      const PopupMenuItem(
                        value: 'resume',
                        child: Text('Продолжить'),
                      ),
                    if (item.active || item.status == 'paused')
                      const PopupMenuItem(
                        value: 'cancel',
                        child: Text('Отменить'),
                      ),
                    if (!item.active &&
                        item.status != 'ready' &&
                        item.status != 'paused')
                      const PopupMenuItem(
                        value: 'retry',
                        child: Text('Повторить'),
                      ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Удалить с устройства'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}
