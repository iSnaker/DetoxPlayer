import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:detox_player/design/detox_theme.dart';
import 'package:detox_player/screens/connect_screen.dart';
import 'package:detox_player/screens/tracks_page.dart';
import 'package:detox_player/widgets/mini_player.dart';
import 'package:detox_player/api/detox_api.dart';
import 'package:detox_player/app_services.dart';
import 'package:detox_player/library/library.dart';
import 'package:detox_player/offline/offline_downloads.dart';
import 'package:detox_player/playlists/playlists.dart';
import 'package:detox_player/player_controller.dart';
import 'package:detox_player/storage/json_store.dart';

import 'library_test.dart' show MemoryCache;
import 'offline_downloads_test.dart' show FakeDownloads;
import 'player_controller_test.dart' show FakePlayer;

class PreviewAudio extends FakePlayer {
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Duration? get duration => const Duration(minutes: 4);
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('DETOX_CAPTURE')) return;
  await tester.runAsync(() async {
    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final folder = Directory('build/design-preview');
    await folder.create(recursive: true);
    await File('${folder.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    const fonts = String.fromEnvironment('DETOX_PREVIEW_FONTS');
    if (fonts.isNotEmpty) {
      final text = FontLoader('Roboto');
      for (final weight in ['regular', 'medium', 'bold']) {
        text.addFont(
          File('$fonts/roboto-$weight.ttf')
              .readAsBytes()
              .then((v) => ByteData.sublistView(v)),
        );
      }
      await text.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File('$fonts/materialicons-regular.otf')
              .readAsBytes()
              .then((v) => ByteData.sublistView(v)),
        );
      await icons.load();
    }
  });
  for (final dark in [false, true]) {
    testWidgets(
      'connection ${dark ? 'night' : 'day'} remains usable with keyboard and large text',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RepaintBoundary(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? DetoxTheme.dark() : DetoxTheme.light(),
              home: ConnectScreen(onConnected: (_) async {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Detox Player'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/avocado.png'),
            tester.element(find.byType(ConnectScreen)),
          ),
        );
        await tester.pumpAndSettle();
        await capture(tester, dark ? 'connect-dark' : 'connect-light');
        tester.view.physicalSize = const Size(320, 568);
        await tester.pumpWidget(
          RepaintBoundary(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? DetoxTheme.dark() : DetoxTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.5),
                  viewInsets: const EdgeInsets.only(bottom: 240),
                ),
                child: child!,
              ),
              home: ConnectScreen(onConnected: (_) async {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Открыть мою музыку'));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('compact player opens full controls and queue at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Directory directory;
    late Services services;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      directory = await Directory.systemTemp.createTemp('detox-design-');
      final api = DetoxApi('http://localhost', 'test');
      final tracks = [
        for (final (i, name) in [
          'Тихий берег',
          'Лёгкий ветер',
          'Вдали от города',
          'После дождя',
          'Медленное утро',
          'Вечерний свет',
          'Без спешки',
        ].indexed)
          {
            'id': '$i',
            'title': name,
            'artist': 'Моя коллекция',
            'album': 'Маленький побег',
            'duration': 240,
          },
      ];
      final cache = MemoryCache()
        ..data =
            '${api.baseUri}\n${jsonEncode({'version': 'v1', 'items': tracks})}';
      final library = Library(api, cache: cache, parseInIsolate: false);
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
        audioPlayer: PreviewAudio(),
        downloads: downloads,
        configureSession: () async {},
      );
      await player.ready;
      await player.playQueue(library.tracks, 0);
      await player.player.pause();
      services = Services(api, library, player, downloads, playlists);
    });
    Widget shell() => Scaffold(
      body: TracksPage(services: services),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayer(controller: services.player, safeBottom: false),
          NavigationBar(
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.music_note_outlined),
                label: 'Треки',
              ),
              NavigationDestination(
                icon: Icon(Icons.album_outlined),
                label: 'Альбомы',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Исполнители',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music),
                label: 'Плейлисты',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                label: 'Настройки',
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DetoxTheme.light(),
          home: shell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, 'library-light');
    await tester.tap(
      find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.text('Тихий берег'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingScreen), findsOneWidget);
    expect(find.byTooltip('Предыдущий'), findsOneWidget);
    expect(find.byTooltip('Перемешать'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'player-light');
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Очередь · 7'));
    await tester.tap(find.text('Очередь · 7'));
    await tester.pumpAndSettle();
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
  });
}
