import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../api/detox_api.dart';
import '../player_controller.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.api, required this.onDisconnect});

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.tracks(
        query: _search.text.trim(),
        offset: _tracks.length,
        limit: _pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _tracks.addAll(page.items);
        _total = page.total;
      });
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      if (e.unauthorized) {
        widget.onDisconnect();
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
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
        bottomNavigationBar: _MiniPlayer(controller: _player),
      );

  Widget _body() {
    if (_tracks.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!),
            TextButton(onPressed: _reload, child: const Text('Повторить')),
          ]),
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
              ? TextButton(onPressed: _loadMore, child: Text('$_error. Повторить'))
              : const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
        }
        final track = _tracks[index];
        return ListTile(
          leading: _Cover(api: widget.api, track: track, size: 48),
          title: Text(track.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [track.displayArtist, if (track.folder.isNotEmpty && track.folder != '.') track.folder]
                .join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _player.play(track),
        );
      },
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.api, required this.track, required this.size});

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
          errorBuilder: (_, _, _) =>
              SizedBox(width: size, height: size, child: const Icon(Icons.music_note)),
        ),
      );
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final track = controller.current;
          if (track == null) return const SizedBox.shrink();
          final player = controller.player;
          return Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, position) => StreamBuilder<Duration?>(
                    stream: player.durationStream,
                    builder: (context, duration) {
                      final total = duration.data ?? Duration.zero;
                      final now = position.data ?? Duration.zero;
                      final max = total.inMilliseconds.toDouble();
                      return Slider(
                        value: max <= 0 ? 0 : now.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                        max: max <= 0 ? 1 : max,
                        onChanged: max <= 0
                            ? null
                            : (v) => player.seek(Duration(milliseconds: v.round())),
                      );
                    },
                  ),
                ),
                ListTile(
                  dense: true,
                  title: Text(track.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    controller.error ?? track.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, state) {
                      final playing = state.data?.playing ?? false;
                      final buffering = state.data?.processingState == ProcessingState.loading ||
                          state.data?.processingState == ProcessingState.buffering;
                      return buffering
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                              onPressed: controller.toggle,
                            );
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      );
}
