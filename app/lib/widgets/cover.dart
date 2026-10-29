import 'package:flutter/material.dart';

import '../api/detox_api.dart';

class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.api,
    required this.track,
    required this.size,
    this.expand = false,
  });

  final DetoxApi api;
  final Track track;
  final double size;

  /// Fills the available box instead of using a fixed [size].
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final side = expand ? double.infinity : size;
    return ClipRRect(
      borderRadius: BorderRadius.circular(expand ? 8 : 4),
      child: Image.network(
        api.resolve(track.coverUrl).toString(),
        headers: api.headers,
        width: side,
        height: side,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, _, _) => SizedBox(
          width: side,
          height: side,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(Icons.music_note, size: expand ? size / 3 : null),
          ),
        ),
      ),
    );
  }
}
