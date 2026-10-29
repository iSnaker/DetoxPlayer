import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../format.dart';

/// Thumb that is a plain dot while idle and a spinning ring while the track is
/// loading or buffering.
class SeekThumbShape extends SliderComponentShape {
  const SeekThumbShape({
    required this.loading,
    required this.spin,
    required this.backdrop,
  });

  final bool loading;

  /// Rotation in turns, 0..1.
  final double spin;

  /// Fill behind the ring so the track does not show through it.
  final Color backdrop;

  static const _dot = 7.0;
  static const _grow = 3.0;
  static const _ring = 11.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_ring + 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final color = sliderTheme.thumbColor ?? Colors.teal;
    if (loading) {
      const radius = _ring - 2;
      canvas.drawCircle(center, _ring, Paint()..color = backdrop);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(
        center,
        radius,
        stroke..color = color.withValues(alpha: 0.25),
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        spin * 2 * math.pi,
        math.pi * 1.2,
        false,
        stroke..color = color,
      );
      canvas.drawCircle(center, 3, Paint()..color = color);
      return;
    }
    final radius = _dot + _grow * activationAnimation.value;
    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      Colors.black,
      2,
      true,
    );
    canvas.drawCircle(center, radius, Paint()..color = color);
  }
}

/// Slider with the buffered part of the track painted ahead of the thumb.
/// It has no player dependency, so it can be tested on its own.
class SeekBarView extends StatefulWidget {
  const SeekBarView({
    super.key,
    required this.position,
    required this.buffered,
    required this.total,
    required this.loading,
    required this.seekable,
    required this.onSeek,
  });

  final Duration position;
  final Duration buffered;
  final Duration total;

  /// The track is loading or stalled: the thumb spins.
  final bool loading;
  final bool seekable;
  final ValueChanged<Duration> onSeek;

  @override
  State<SeekBarView> createState() => _SeekBarViewState();
}

class _SeekBarViewState extends State<SeekBarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// Value under the finger, kept after release until the player reports a
  /// new position, so the thumb does not jump back.
  double? _held;

  @override
  void initState() {
    super.initState();
    if (widget.loading) _spin.repeat();
  }

  @override
  void didUpdateWidget(SeekBarView old) {
    super.didUpdateWidget(old);
    if (widget.loading && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.loading && _spin.isAnimating) {
      _spin.stop();
    }
    if (old.position != widget.position && !_dragging) _held = null;
  }

  bool _dragging = false;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall;
    final totalMs = widget.total.inMilliseconds.toDouble();
    final known = totalMs > 0;
    final shown = known
        ? (_held ?? widget.position.inMilliseconds.toDouble()).clamp(
            0.0,
            totalMs,
          )
        : 0.0;
    final buffered = known
        ? widget.buffered.inMilliseconds.toDouble().clamp(shown, totalMs)
        : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _spin,
          builder: (context, _) => SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: scheme.primary,
              inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.12),
              secondaryActiveTrackColor: scheme.primary.withValues(alpha: 0.35),
              thumbColor: scheme.primary,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              thumbShape: SeekThumbShape(
                loading: widget.loading,
                spin: _spin.value,
                backdrop: scheme.surface,
              ),
            ),
            child: Slider(
              value: shown,
              secondaryTrackValue: buffered,
              max: known ? totalMs : 1,
              onChangeStart: widget.seekable && known
                  ? (_) => _dragging = true
                  : null,
              onChanged: widget.seekable && known
                  ? (v) => setState(() => _held = v)
                  : null,
              onChangeEnd: widget.seekable && known
                  ? (v) {
                      _dragging = false;
                      setState(() => _held = v);
                      widget.onSeek(Duration(milliseconds: v.round()));
                    }
                  : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(clock(Duration(milliseconds: shown.round())), style: style),
              Text(clock(widget.total), style: style),
            ],
          ),
        ),
      ],
    );
  }
}

/// Connects [SeekBarView] to the audio player.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, required this.player, this.fallbackTotal});

  final AudioPlayer player;

  /// Length from library metadata, used until the player knows the duration.
  final Duration? fallbackTotal;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  final _subscriptions = <StreamSubscription<Object?>>[];
  late Duration _position = widget.player.position;
  late Duration _buffered = widget.player.bufferedPosition;
  late Duration? _duration = widget.player.duration;
  late ProcessingState _state = widget.player.processingState;

  @override
  void initState() {
    super.initState();
    final player = widget.player;
    void listen<T>(Stream<T> stream, void Function(T value) apply) {
      _subscriptions.add(
        stream.listen((value) {
          if (!mounted) return;
          setState(() => apply(value));
        }),
      );
    }

    listen(player.positionStream, (v) => _position = v);
    listen(player.bufferedPositionStream, (v) => _buffered = v);
    listen(player.durationStream, (v) => _duration = v);
    listen(player.processingStateStream, (v) => _state = v);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading =
        _state == ProcessingState.loading ||
        _state == ProcessingState.buffering;
    return SeekBarView(
      position: _position,
      buffered: _buffered,
      total: _duration ?? widget.fallbackTotal ?? Duration.zero,
      loading: loading,
      seekable:
          _duration != null &&
          _state != ProcessingState.idle &&
          _state != ProcessingState.loading,
      onSeek: widget.player.seek,
    );
  }
}
