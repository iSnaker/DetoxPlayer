import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../player_controller.dart';
import 'cover.dart';
import 'equalizer_icon.dart';

/// The play queue. Swipe a row to the left to remove it; the pencil switches
/// to editing, where upcoming tracks can be dragged by the handle.
class QueueSheet extends StatefulWidget {
  const QueueSheet({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  static const _rowHeight = 72.0;

  bool _editing = false;

  PlayerController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    maxChildSize: 0.9,
    builder: (context, scroll) {
      return ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final queue = _controller.upcomingQueue;
          // The same track can be queued twice, so keys count repeats.
          final seen = <String, int>{};
          final keys = [
            for (final t in queue)
              ValueKey('${t.id}#${seen[t.id] = (seen[t.id] ?? 0) + 1}'),
          ];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Очередь · ${queue.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: _editing ? 'Готово' : 'Изменить очередь',
                      icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
                      onPressed: () => setState(() => _editing = !_editing),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: scroll,
                  buildDefaultDragHandles: false,
                  itemExtent: _rowHeight,
                  itemCount: queue.length,
                  onReorderItem: (from, to) => _controller.moveInQueue(
                    from + _controller.index,
                    to + _controller.index,
                  ),
                  itemBuilder: (context, i) => _row(context, i, keys[i]),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  Widget _row(BuildContext context, int i, Key key) {
    final track = _controller.upcomingQueue[i];
    final scheme = Theme.of(context).colorScheme;
    final current = i == 0;
    final upcoming = i > 0;
    return Slidable(
      key: key,
      enabled: !current,
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.3,
        children: [
          SlidableAction(
            onPressed: (_) =>
                _controller.removeFromQueue(i + _controller.index),
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            icon: Icons.delete_outline,
            label: 'Удалить',
          ),
        ],
      ),
      child: ListTile(
        selected: current,
        leading: Cover(api: _controller.api, track: track, size: 40),
        title: Text(
          track.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          track.displayArtist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (current)
              StreamBuilder<bool>(
                stream: _controller.player.playingStream,
                initialData: _controller.player.playing,
                builder: (context, playing) => EqualizerIcon(
                  playing: playing.data ?? false,
                  color: scheme.primary,
                ),
              ),
            if (_editing && upcoming)
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle),
                ),
              ),
          ],
        ),
        onTap: _editing
            ? null
            : () => _controller.jumpTo(i + _controller.index),
      ),
    );
  }
}
