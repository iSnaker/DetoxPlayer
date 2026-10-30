import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../player_controller.dart';
import 'cover.dart';
import 'queue_sheet.dart';
import 'seek_bar.dart';

/// A quiet, compact bar; all playback controls remain available on expansion.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.controller,
    this.safeBottom = true,
  });
  final PlayerController controller;
  final bool safeBottom;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final track = controller.current;
      if (track == null) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      return SafeArea(
        top: false,
        bottom: safeBottom,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Material(
            color: scheme.secondaryContainer,
            elevation: 0,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => NowPlayingScreen(controller: controller),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                child: Row(
                  children: [
                    Cover(api: controller.api, track: track, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            controller.error == null
                                ? track.displayArtist
                                : 'Ошибка загрузки',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    _PlayButton(controller: controller, compact: true),
                    IconButton(
                      tooltip: controller.error == null
                          ? 'Следующий'
                          : 'Повторить',
                      onPressed: controller.error == null
                          ? controller.next
                          : controller.retry,
                      icon: Icon(
                        controller.error == null
                            ? Icons.skip_next_rounded
                            : Icons.refresh_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key, required this.controller});
  final PlayerController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final track = controller.current;
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Свернуть плеер',
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Сейчас играет',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
        ),
        body: track == null
            ? const Center(child: Text('Выберите музыку'))
            : SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: scheme.secondary.withValues(
                                        alpha: 0.16,
                                      ),
                                      blurRadius: 36,
                                      offset: const Offset(0, 16),
                                    ),
                                  ],
                                ),
                                child: Cover(
                                  api: controller.api,
                                  track: track,
                                  size: 360,
                                  expand: true,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              track.displayTitle,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              track.displayArtist,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: scheme.primary),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (controller.error != null)
                            TextButton.icon(
                              onPressed: controller.retry,
                              icon: const Icon(Icons.refresh),
                              label: Text(controller.error!),
                            ),
                          SeekBar(
                            player: controller.player,
                            fallbackTotal: track.duration == null
                                ? null
                                : Duration(
                                    milliseconds: (track.duration! * 1000)
                                        .round(),
                                  ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _ShuffleButton(controller: controller),
                              IconButton(
                                tooltip: 'Предыдущий',
                                iconSize: 32,
                                icon: const Icon(Icons.skip_previous_rounded),
                                onPressed: controller.previous,
                              ),
                              _PlayButton(controller: controller),
                              IconButton(
                                tooltip: 'Следующий',
                                iconSize: 32,
                                icon: const Icon(Icons.skip_next_rounded),
                                onPressed: controller.next,
                              ),
                              _LoopButton(controller: controller),
                            ],
                          ),
                          const SizedBox(height: 24),
                          TextButton.icon(
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) =>
                                  QueueSheet(controller: controller),
                            ),
                            icon: const Icon(Icons.queue_music_rounded),
                            label: Text('Очередь · ${controller.queue.length}'),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'DETOX PLAYER',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2.4,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      );
    },
  );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.controller, this.compact = false});
  final bool compact;

  final PlayerController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: controller.player.playingStream,
    initialData: controller.player.playing,
    builder: (context, state) {
      final playing = state.data ?? false;
      return SizedBox(
        width: compact ? 48 : 72,
        height: compact ? 48 : 72,
        child: IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: compact
                ? Colors.transparent
                : Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          tooltip: playing ? 'Пауза' : 'Играть',
          iconSize: compact ? 30 : 44,
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
