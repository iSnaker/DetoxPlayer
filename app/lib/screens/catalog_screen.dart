import 'dart:async';

import 'package:flutter/material.dart';

import '../api/detox_api.dart';
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
  static const _pageSize = 50;

  late final PlayerController _player = PlayerController(widget.api);
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _tracks = <Track>[];
  Timer? _debounce;
  int _total = 0;
  int _generation = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    _player.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  Future<void> _reload() async {
    _generation++;
    setState(() {
      _tracks.clear();
      _total = 0;
      _error = null;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || (_tracks.isNotEmpty && _tracks.length >= _total)) return;
    final generation = _generation;
    final query = _search.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.tracks(
        query: query,
        offset: _tracks.length,
        limit: _pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _tracks.addAll(page.items);
        _total = page.total;
      });
      _player.extendQueue(page.items, key: query);
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      if (e.unauthorized) {
        widget.onDisconnect();
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
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
          tooltip: 'Отключиться',
          icon: const Icon(Icons.logout),
          onPressed: widget.onDisconnect,
        ),
      ],
    ),
    body: _body(),
    bottomNavigationBar: MiniPlayer(controller: _player),
  );

  Widget _body() {
    if (_tracks.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              TextButton(onPressed: _reload, child: const Text('Повторить')),
            ],
          ),
        );
      }
      return const Center(child: Text('Ничего не найдено'));
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: _tracks.length + (_loading || _error != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _tracks.length) {
          return _error != null
              ? TextButton(
                  onPressed: _loadMore,
                  child: Text('$_error. Повторить'),
                )
              : const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
        }
        final track = _tracks[index];
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
              if (track.folder.isNotEmpty && track.folder != '.') track.folder,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _player.playQueue(
            List.of(_tracks),
            index,
            key: _search.text.trim(),
          ),
        );
      },
    );
  }
}
