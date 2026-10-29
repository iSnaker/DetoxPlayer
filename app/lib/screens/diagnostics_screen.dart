import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../diagnostics/diagnostics.dart';
import '../widgets/library_actions.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final logs = Diagnostics.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал диагностики'),
        actions: [
          IconButton(
            tooltip: 'Копировать журнал',
            icon: const Icon(Icons.copy),
            onPressed: () => runAction(context, () async {
              await Clipboard.setData(ClipboardData(text: await logs.export()));
            }, success: 'Журнал скопирован'),
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: 'Экспорт журнала',
              icon: const Icon(Icons.ios_share),
              onPressed: () => runAction(context, () async {
                final box = buttonContext.findRenderObject() as RenderBox;
                final origin = box.localToGlobal(Offset.zero) & box.size;
                final content = await logs.export();
                await SharePlus.instance.share(
                  ShareParams(
                    files: [
                      XFile.fromData(
                        utf8.encode(content),
                        mimeType: 'text/plain',
                      ),
                    ],
                    fileNameOverrides: ['detox-diagnostics.json'],
                    sharePositionOrigin: origin,
                  ),
                );
              }),
            ),
          ),
          IconButton(
            tooltip: 'Очистить журнал',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => runAction(context, logs.clear),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: logs,
        builder: (context, _) {
          final entries = logs.entries;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  logs.storageError ?? 'Последние 800 событий. Ключи и URL скрыты. После ошибки экспортируйте журнал до повторного теста.',
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return ListTile(
                      dense: true,
                      title: Text('${e['time']} · ${e['event']}'),
                      subtitle: SelectableText(
                        jsonEncode(
                          Map.of(e)
                            ..remove('time')
                            ..remove('event'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
