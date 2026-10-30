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
      borderRadius: BorderRadius.circular(expand ? 20 : 10),
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.secondaryContainer,
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ],
              ),
            ),
            child: Center(
              child: Icon(
                Icons.music_note_rounded,
                size: expand ? size / 3 : 24,
                color: Theme.of(context).colorScheme.secondary
                    .withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
