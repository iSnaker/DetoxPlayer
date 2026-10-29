import 'package:flutter/material.dart';

import '../app_services.dart';
import '../format.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.services,
    required this.onDisconnect,
  });

  final Services services;
  final VoidCallback onDisconnect;

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти?'),
        content: const Text(
          'Ключ устройства будет удалён с телефона, воспроизведение '
          'остановится. Чтобы войти снова, понадобится ключ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (ok == true) onDisconnect();
  }

  @override
  Widget build(BuildContext context) {
    final library = services.library;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) => ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Сервер'),
              subtitle: Text(services.api.baseUri.toString()),
            ),
            ListTile(
              leading: library.syncing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              title: const Text('Обновить медиатеку'),
              subtitle: Text(
                library.syncError ??
                    (library.syncing
                        ? 'Загрузка списка…'
                        : '${tracksText(library.tracks.length)} в списке'),
              ),
              enabled: !library.syncing,
              onTap: () => library.sync(force: true),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Выйти'),
              onTap: () => _confirmLogout(context),
            ),
          ],
        ),
      ),
    );
  }
}
