import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../player_controller.dart';
import 'cover.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.controller});

  final PlayerController controller;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SeekBar(player: player),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _showQueue(context),
                        child: Row(
                          children: [
                            Cover(api: controller.api, track: track, size: 40),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    controller.error ?? track.displayArtist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _ShuffleButton(controller: controller),
                    IconButton(
                      tooltip: 'Предыдущий',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.skip_previous),
                      onPressed: controller.previous,
                    ),
                    _PlayButton(controller: controller),
                    IconButton(
                      tooltip: 'Следующий',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.skip_next),
                      onPressed: controller.next,
                    ),
                    _LoopButton(controller: controller),
                  ],
                ),
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

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.player});

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: player.positionStream,
    builder: (context, position) => StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, duration) {
        final total = duration.data ?? Duration.zero;
        final now = position.data ?? Duration.zero;
        final max = total.inMilliseconds.toDouble();
        return Slider(
          value: max <= 0
              ? 0
              : now.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
          max: max <= 0 ? 1 : max,
          onChanged: max <= 0
              ? null
              : (v) => player.seek(Duration(milliseconds: v.round())),
        );
      },
    ),
  );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<PlayerState>(
    stream: controller.player.playerStateStream,
    builder: (context, state) {
      final playing = state.data?.playing ?? false;
      final buffering =
          state.data?.processingState == ProcessingState.loading ||
          state.data?.processingState == ProcessingState.buffering;
      return SizedBox(
        width: 48,
        height: 48,
        child: buffering && playing
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: playing ? 'Пауза' : 'Играть',
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
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: controller.player.shuffleModeEnabledStream,
    builder: (context, snapshot) => IconButton(
      tooltip: 'Перемешать',
      visualDensity: VisualDensity.compact,
      isSelected: snapshot.data ?? false,
      icon: const Icon(Icons.shuffle),
      onPressed: controller.toggleShuffle,
    ),
  );
}

class _LoopButton extends StatelessWidget {
  const _LoopButton({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<LoopMode>(
    stream: controller.player.loopModeStream,
    builder: (context, snapshot) {
      final mode = snapshot.data ?? LoopMode.off;
      return IconButton(
        tooltip: switch (mode) {
          LoopMode.off => 'Повтор выключен',
          LoopMode.all => 'Повторять очередь',
          LoopMode.one => 'Повторять трек',
        },
        visualDensity: VisualDensity.compact,
        isSelected: mode != LoopMode.off,
        icon: Icon(mode == LoopMode.one ? Icons.repeat_one : Icons.repeat),
        onPressed: controller.cycleLoopMode,
      );
    },
  );
}

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    maxChildSize: 0.9,
    builder: (context, scroll) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final queue = controller.queue;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Очередь · ${queue.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: queue.length,
                itemBuilder: (context, i) {
                  final track = queue[i];
                  final selected = i == controller.index;
                  return ListTile(
                    selected: selected,
                    leading: Cover(api: controller.api, track: track, size: 40),
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
                    trailing: selected ? const Icon(Icons.equalizer) : null,
                    onTap: () => controller.jumpTo(i),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
