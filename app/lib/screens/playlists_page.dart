import 'package:flutter/material.dart';

class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Плейлисты')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music, size: 64),
            SizedBox(height: 12),
            Text(
              'Плейлисты появятся в одном из следующих обновлений',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
