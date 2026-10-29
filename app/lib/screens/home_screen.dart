import '../offline/offline_downloads.dart';
import '../playlists/playlists.dart';

import 'package:flutter/material.dart';

import '../api/detox_api.dart';
import '../app_services.dart';
import '../library/library.dart';
import '../player_controller.dart';
import '../widgets/mini_player.dart';
import 'albums_page.dart';
import 'artists_screen.dart';
import 'playlists_page.dart';
import 'settings_page.dart';
import 'tracks_page.dart';

/// The signed-in shell: five sections, the mini player always above the bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.onDisconnect});

  final DetoxApi api;
  final VoidCallback onDisconnect;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Library _library = Library(widget.api);
  late final OfflineDownloads _downloads = OfflineDownloads(widget.api);
  late final Playlists _playlists = Playlists(widget.api.baseUri.toString());
  late final PlayerController _player = PlayerController(
    widget.api,
    _library,
    downloads: _downloads,
  );
  late final Services _services = Services(
    widget.api,
    _library,
    _player,
    _downloads,
    _playlists,
  );
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _downloads.ready;
    _playlists.ready;
    _library.loaded.then((_) {
      if (mounted) _library.sync();
    });
  }

  @override
  void dispose() {
    _downloads.dispose();
    _playlists.dispose();
    _player.dispose();
    _library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [
        TracksPage(services: _services),
        AlbumsPage(services: _services),
        ArtistsPage(services: _services),
        PlaylistsPage(services: _services),
        SettingsPage(services: _services, onDisconnect: widget.onDisconnect),
      ],
    ),
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MiniPlayer(controller: _player, safeBottom: false),
        NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.music_note_outlined),
              selectedIcon: Icon(Icons.music_note),
              label: 'Треки',
            ),
            NavigationDestination(
              icon: Icon(Icons.album_outlined),
              selectedIcon: Icon(Icons.album),
              label: 'Альбомы',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Исполнители',
            ),
            NavigationDestination(
              icon: Icon(Icons.queue_music_outlined),
              selectedIcon: Icon(Icons.queue_music),
              label: 'Плейлисты',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Настройки',
            ),
          ],
        ),
      ],
    ),
  );
}
