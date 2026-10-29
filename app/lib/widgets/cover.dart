import 'package:flutter/material.dart';

import '../api/detox_api.dart';

class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.api,
    required this.track,
    required this.size,
  });

  final DetoxApi api;
  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: Image.network(
      api.resolve(track.coverUrl).toString(),
      headers: api.headers,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * 3).round(),
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.music_note),
      ),
    ),
  );
}
