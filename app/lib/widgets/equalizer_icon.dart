import 'package:flutter/material.dart';

/// Three bouncing bars; they freeze when [playing] is false.
class EqualizerIcon extends StatefulWidget {
  const EqualizerIcon({
    super.key,
    required this.playing,
    required this.color,
    this.size = 20,
  });

  final bool playing;
  final Color color;
  final double size;

  @override
  State<EqualizerIcon> createState() => _EqualizerIconState();
}

class _EqualizerIconState extends State<EqualizerIcon>
    with SingleTickerProviderStateMixin {
  static const _phases = [0.0, 0.33, 0.66];
  static const _frozen = [0.45, 0.8, 0.6];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(EqualizerIcon old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _height(int bar) {
    if (!widget.playing) return _frozen[bar];
    final t = (_controller.value + _phases[bar]) % 1.0;
    final wave = t < 0.5 ? t * 2 : (1 - t) * 2;
    return 0.25 + 0.75 * wave;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: widget.size / 5,
              height: widget.size * _height(i),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    ),
  );
}
