import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:detox_player/api/detox_api.dart';
import 'package:detox_player/app_services.dart';
import 'package:detox_player/library/library.dart';
import 'package:detox_player/library/groups.dart';
import 'package:detox_player/offline/offline_downloads.dart';
import 'package:detox_player/playlists/playlists.dart';
import 'package:detox_player/player_controller.dart';
import 'package:detox_player/screens/album_screen.dart';
import 'package:detox_player/storage/json_store.dart';

import 'library_test.dart' show MemoryCache;
import 'offline_downloads_test.dart' show FakeDownloads;
import 'player_controller_test.dart' show FakePlayer;

void main() {
  testWidgets(
    'album actions fit a narrow phone and expose track download menu',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory directory;
      late Services services;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        directory = await Directory.systemTemp.createTemp('detox-ui-');
        final api = DetoxApi('http://localhost', 'test');
        final library = Library(api, cache: MemoryCache());
        final downloads = OfflineDownloads(
          api,
          backend: FakeDownloads(),
          store: JsonStore('downloads', directory: directory),
          directory: directory,
        );
        await downloads.ready;
        final playlists = Playlists(
          'server',
          store: JsonStore('playlists', directory: directory),
        );
        await playlists.ready;
        final player = PlayerController(
          api,
          library,
          audioPlayer: FakePlayer(),
          downloads: downloads,
          configureSession: () async {},
        );
        await player.ready;
        services = Services(api, library, player, downloads, playlists);
      });
      final album = Album('Очень длинное название альбома', 'folder', [
        Track.fromJson({'id': 'one', 'title': 'Трек'}),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: AlbumScreen(services: services, album: album),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Добавить альбом в плейлист'), findsOneWidget);
      expect(find.byTooltip('Скачать альбом'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final add = tester.getTopLeft(
        find.byTooltip('Добавить альбом в плейлист'),
      );
      final shuffle = tester.getTopLeft(find.byTooltip('Перемешать'));
      expect(
        add.dy < shuffle.dy || (add.dy == shuffle.dy && add.dx < shuffle.dx),
        true,
      );
      await tester.tap(find.byTooltip('Действия'));
      await tester.pumpAndSettle();
      expect(find.text('Скачать для офлайн'), findsOneWidget);
      expect(find.text('Добавить в плейлист'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        services.player.dispose();
        services.downloads.dispose();
        services.playlists.dispose();
        services.library.dispose();
        services.api.close();
        await directory.delete(recursive: true);
      });
    },
  );
}
