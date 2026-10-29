import '../diagnostics/diagnostics.dart';

import 'package:flutter/material.dart';

import '../api/detox_api.dart';
import '../app_services.dart';
import '../playlists/playlists.dart';

Future<void> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    }
  } on Object catch (e, st) {
    Diagnostics.instance.event('ui.action_error', {'message': e, 'stack': st});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось выполнить действие. Проверьте свободное место и журнал.',
          ),
        ),
      );
    }
  }
}

Future<String?> playlistName(BuildContext context, {String? initial}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        initial == null ? 'Новый плейлист' : 'Переименовать плейлист',
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Название'),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  // The dialog may still be animating out when its route future resolves.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}

Future<void> addToPlaylist(
  BuildContext context,
  Services services,
  List<Track> tracks,
) async {
  await services.playlists.ready;
  if (!context.mounted) return;
  final selected = await showModalBottomSheet<Object>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Добавить в плейлист')),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Создать плейлист'),
            onTap: () => Navigator.pop(context, 'new'),
          ),
          for (final p in services.playlists.items)
            ListTile(
              title: Text(p.name),
              subtitle: Text('${p.tracks.length} треков'),
              onTap: () => Navigator.pop(context, p),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || selected == null) return;
  await runAction(context, () async {
    Playlist? target = selected is Playlist ? selected : null;
    if (target == null) {
      final name = await playlistName(context);
      if (name == null) return;
      target = await services.playlists.create(name);
    }
    await services.playlists.add(target, tracks);
  }, success: 'Плейлист обновлён');
}
