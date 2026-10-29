import 'dart:async';

import 'package:flutter/material.dart';

import '../api/detox_api.dart';
import '../library/library.dart';
import '../player_controller.dart';
import '../widgets/cover.dart';
import '../widgets/mini_player.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.api,
    required this.onDisconnect,
  });

  final DetoxApi api;
  final VoidCallback onDisconnect;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final Library _library = Library(widget.api);
  late final PlayerController _player = PlayerController(widget.api, _library);
  final _search = TextEditingController();
  Timer? _debounce;
  List<Track> _visible = const [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _library.addListener(_onLibraryChanged);
    _library.loaded.then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _sync();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _library.removeListener(_onLibraryChanged);
    _search.dispose();
    _player.dispose();
    _library.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    if (!mounted) return;
    setState(() => _visible = _library.search(_search.text));
    if (_library.unauthorized) widget.onDisconnect();
  }

  Future<void> _sync({bool force = false}) => _library.sync(force: force);

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _visible = _library.search(_search.text));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        controller: _search,
        onChanged: _onSearchChanged,
        decoration: const InputDecoration(
          hintText: 'Поиск',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Перемешать и играть',
          icon: const Icon(Icons.shuffle),
          onPressed: _visible.isEmpty
              ? null
              : () => _player.playShuffled(_visible),
        ),
        IconButton(
          tooltip: 'Обновить медиатеку',
          icon: const Icon(Icons.refresh),
          onPressed: _library.syncing ? null : () => _sync(force: true),
        ),
        IconButton(
          tooltip: 'Отключиться',
          icon: const Icon(Icons.logout),
          onPressed: widget.onDisconnect,
        ),
      ],
      bottom: _library.syncing
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : null,
    ),
    body: _body(),
    bottomNavigationBar: MiniPlayer(controller: _player),
  );

  Widget _body() {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    final error = _library.syncError;
    if (_library.tracks.isEmpty) {
      if (_library.syncing) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error ?? 'Медиатека пуста'),
            TextButton(
              onPressed: () => _sync(force: true),
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
                onPressed: () => _sync(force: true),
                child: const Text('Повторить'),
              ),
            ],
          ),
        Expanded(
          child: _visible.isEmpty
              ? const Center(child: Text('Ничего не найдено'))
              : ListView.builder(
                  itemExtent: 72,
                  itemCount: _visible.length,
                  itemBuilder: (context, index) {
                    final track = _visible[index];
                    return ListTile(
                      leading: Cover(api: widget.api, track: track, size: 48),
                      title: Text(
                        track.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          track.displayArtist,
                          if (track.folder.isNotEmpty && track.folder != '.')
                            track.folder,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _player.playQueue(_visible, index),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
