import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../player_controller.dart';
import 'cover.dart';
import 'queue_sheet.dart';
import 'seek_bar.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.controller,
    this.safeBottom = true,
  });

  final PlayerController controller;

  /// False when a navigation bar below already handles the system inset.
  final bool safeBottom;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final track = controller.current;
      if (track == null) return const SizedBox.shrink();
      final player = controller.player;
      return Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          bottom: safeBottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => _showQueue(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Cover(api: controller.api, track: track, size: 80),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              controller.error ?? track.displayArtist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (controller.error != null)
                TextButton.icon(
                  onPressed: controller.retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Повторить'),
                ),
              SeekBar(
                player: player,
                fallbackTotal: track.duration == null
                    ? null
                    : Duration(milliseconds: (track.duration! * 1000).round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ShuffleButton(controller: controller),
                  IconButton(
                    tooltip: 'Предыдущий',
                    iconSize: 36,
                    icon: const Icon(Icons.skip_previous),
                    onPressed: controller.previous,
                  ),
                  _PlayButton(controller: controller),
                  IconButton(
                    tooltip: 'Следующий',
                    iconSize: 36,
                    icon: const Icon(Icons.skip_next),
                    onPressed: controller.next,
                  ),
                  _LoopButton(controller: controller),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  void _showQueue(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => QueueSheet(controller: controller),
  );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: controller.player.playingStream,
    initialData: controller.player.playing,
    builder: (context, state) {
      final playing = state.data ?? false;
      return SizedBox(
        width: 72,
        height: 72,
        child: IconButton(
          tooltip: playing ? 'Пауза' : 'Играть',
          iconSize: 56,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: controller.toggle,
        ),
      );
    },
  );
}

class _ShuffleButton extends StatelessWidget {
  const _ShuffleButton({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Перемешать',
    isSelected: controller.shuffle,
    icon: const Icon(Icons.shuffle),
    onPressed: controller.toggleShuffle,
  );
}

class _LoopButton extends StatelessWidget {
  const _LoopButton({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final mode = controller.loop;
    return IconButton(
      tooltip: switch (mode) {
        LoopMode.off => 'Повтор выключен',
        LoopMode.all => 'Повторять очередь',
        LoopMode.one => 'Повторять трек',
      },
      isSelected: mode != LoopMode.off,
      icon: Icon(mode == LoopMode.one ? Icons.repeat_one : Icons.repeat),
      onPressed: controller.cycleLoopMode,
    );
  }
}
