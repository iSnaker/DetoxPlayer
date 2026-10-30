import 'package:flutter/material.dart';

import '../api/detox_api.dart';
import '../app_services.dart';
import '../library/groups.dart';
import 'cover.dart';

/// Phones show two columns, large phones three, tablets and desktop more.
int albumColumns(double width) {
  if (width >= 1000) return 5;
  if (width >= 700) return 4;
  if (width >= 430) return 3;
  return 2;
}

class AlbumGrid extends StatelessWidget {
  const AlbumGrid({
    super.key,
    required this.services,
    required this.albums,
    required this.onOpen,
    this.header,
  });

  final Services services;
  final List<Album> albums;
  final void Function(Album album) onOpen;
  final Widget? header;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => CustomScrollView(
      slivers: [
        if (header != null) SliverToBoxAdapter(child: header),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: albumColumns(constraints.maxWidth),
              mainAxisSpacing: 24,
              crossAxisSpacing: 18,
              childAspectRatio: MediaQuery.textScalerOf(context).scale(14) > 20
                  ? 0.60
                  : 0.74,
            ),
            itemCount: albums.length,
            itemBuilder: (context, i) => _AlbumCard(
              api: services.api,
              album: albums[i],
              onTap: () => onOpen(albums[i]),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.api,
    required this.album,
    required this.onTap,
  });

  final DetoxApi api;
  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Cover(
              api: api,
              track: album.cover,
              size: box.biggest.shortestSide,
              expand: true,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          album.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          album.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
