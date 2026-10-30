import '../design/brand.dart';

import 'package:flutter/material.dart';

import '../api/detox_api.dart';

const _testServerUrl = String.fromEnvironment(
  'DETOX_TEST_SERVER_URL',
  defaultValue: 'http://127.0.0.1:8081',
);
const _testDeviceKey = String.fromEnvironment('DETOX_TEST_DEVICE_KEY');

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.onConnected, this.initialUrl});

  final Future<void> Function(DetoxApi api) onConnected;
  final String? initialUrl;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final _url = TextEditingController(
    text: widget.initialUrl?.isNotEmpty == true
        ? widget.initialUrl
        : _testServerUrl,
  );
  final _key = TextEditingController(text: _testDeviceKey);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    DetoxApi? api;
    try {
      api = DetoxApi(_url.text, _key.text.trim());
      await api.deviceName();
      await widget.onConnected(api);
    } on ApiException catch (e) {
      api?.close();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandMark(size: 140)),
                const SizedBox(height: 28),
                Text(
                  'Detox Player',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontSize: 38),
                ),
                const SizedBox(height: 10),
                Text(
                  'Музыка. И ничего лишнего.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'Ваше тихое место',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Подключите свою медиатеку и оставьте шум снаружи.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Адрес сервера',
                    hintText: 'http://127.0.0.1:8081',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _key,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Ключ устройства',
                  ),
                  onSubmitted: (_) => _busy ? null : _connect(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Открыть мою музыку'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
