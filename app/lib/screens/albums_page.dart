import 'package:flutter/material.dart';

import '../app_services.dart';
import '../widgets/album_grid.dart';
import 'album_screen.dart';

class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key, required this.services});

  final Services services;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Альбомы')),
    body: ListenableBuilder(
      listenable: services.library,
      builder: (context, _) {
        final albums = services.library.albums;
        if (albums.isEmpty) {
          return const Center(child: Text('Медиатека пуста'));
        }
        return AlbumGrid(
          services: services,
          albums: albums,
          onOpen: (album) => openAlbum(context, services, album),
        );
      },
    ),
  );
}
