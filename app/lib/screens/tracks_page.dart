import '../design/brand.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/detox_api.dart';
import '../app_services.dart';
import '../widgets/track_tile.dart';

/// All tracks with search. The whole list is in memory; the list builder only
/// creates the rows that are on screen.
class TracksPage extends StatefulWidget {
  const TracksPage({super.key, required this.services});

  final Services services;

  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  Services get _s => widget.services;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _query = text);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _s.library,
    builder: (context, _) {
      final visible = _s.library.search(_query);
      return Scaffold(
        appBar: libraryAppBar(
          context,
          'Моя музыка',
          actions: [
            IconButton(
              tooltip: 'Перемешать и играть',
              icon: const Icon(Icons.shuffle_rounded),
              onPressed: visible.isEmpty
                  ? null
                  : () => _s.player.playShuffled(visible),
            ),
            const SizedBox(width: 12),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      hintText: 'Найти свою музыку',
                      prefixIcon: Icon(Icons.search_rounded),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  if (_s.library.syncing)
                    const LinearProgressIndicator(minHeight: 2),
                ],
              ),
            ),
          ),
        ),
        body: _body(visible),
      );
    },
  );

  Widget _body(List<Track> visible) {
    final library = _s.library;
    final error = library.syncError;
    if (library.tracks.isEmpty) {
      if (library.syncing) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error ?? 'Медиатека пуста'),
            TextButton(
              onPressed: () => library.sync(force: true),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (error != null)
          MaterialBanner(
            content: Text('$error. Показана сохранённая копия.'),
            actions: [
              TextButton(
                onPressed: () => library.sync(force: true),
                child: const Text('Повторить'),
              ),
            ],
          ),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('Ничего не найдено'))
              : ListView.builder(
                  itemExtent: MediaQuery.textScalerOf(context).scale(16) > 22
                      ? 94
                      : 76,
                  itemCount: visible.length,
                  itemBuilder: (context, i) => TrackTile(
                    services: _s,
                    track: visible[i],
                    onTap: () => _s.player.playQueue(visible, i),
                  ),
                ),
        ),
      ],
    );
  }
}
