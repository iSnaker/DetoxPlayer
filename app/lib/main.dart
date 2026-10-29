import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api/connection_store.dart';
import 'api/detox_api.dart';
import 'screens/catalog_screen.dart';
import 'screens/connect_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.detox.detox_player.playback',
    androidNotificationChannelName: 'Воспроизведение',
    androidNotificationOngoing: true,
  );
  runApp(const DetoxApp());
}

class DetoxApp extends StatelessWidget {
  const DetoxApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DetoxPlayer',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const Root(),
  );
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  final _store = ConnectionStore();
  DetoxApi? _api;
  String? _lastUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final saved = await _store.load();
    final lastUrl = await _store.lastUrl();
    if (!mounted) return;
    setState(() {
      _lastUrl = lastUrl;
      if (saved != null) _api = DetoxApi(saved.url, saved.key);
      _loading = false;
    });
  }

  Future<void> _disconnect() async {
    await _store.clearKey();
    _api?.close();
    if (!mounted) return;
    setState(() {
      _lastUrl = _api?.baseUri.toString();
      _api = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final api = _api;
    if (api == null) {
      return ConnectScreen(
        initialUrl: _lastUrl,
        onConnected: (api) async {
          await _store.save(Connection(api.baseUri.toString(), api.key));
          setState(() => _api = api);
        },
      );
    }
    return CatalogScreen(
      key: ValueKey(api.key),
      api: api,
      onDisconnect: _disconnect,
    );
  }
}
