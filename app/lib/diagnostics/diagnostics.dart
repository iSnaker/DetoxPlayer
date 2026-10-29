import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/json_store.dart';

class Diagnostics extends ChangeNotifier {
  Diagnostics({JsonStore? store}) : _store = store ?? JsonStore('diagnostics');
  static final instance = Diagnostics();
  final JsonStore _store;
  final List<Map<String, dynamic>> _entries = [];
  final Set<String> _secrets = {};
  static const capacity = 800;
  Timer? _flush;
  String? storageError;
  late final Future<void> ready = _load();
  List<Map<String, dynamic>> get entries =>
      List.unmodifiable(_entries.reversed);
  void registerSecret(String secret) {
    if (secret.isNotEmpty) _secrets.add(secret);
  }

  String redact(String value) {
    var text = value;
    for (final secret in _secrets) {
      text = text.replaceAll(secret, '[secret]');
    }
    text = text.replaceAll(RegExp(r'dtp_[A-Za-z0-9_-]+'), '[key]');
    text = text.replaceAll(
      RegExp(r'Bearer\s+[^\s,;"}]+', caseSensitive: false),
      'Bearer [secret]',
    );
    text = text.replaceAll(RegExp(r'https?://[^\s"<>]+'), '[url]');
    return text.length > 1200 ? text.substring(0, 1200) : text;
  }

  Future<void> _load() async {
    try {
      final saved = await _store.read();
      final old = (saved['events'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _entries.insertAll(0, old);
      _trim();
    } on Object {
      storageError = 'Не удалось прочитать предыдущий журнал';
    }
  }

  void _trim() {
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
  }

  void event(String event, [Map<String, Object?> fields = const {}]) {
    final safe = <String, Object?>{};
    for (final item in fields.entries) {
      if (RegExp(
        'key|token|cookie|authorization|header',
        caseSensitive: false,
      ).hasMatch(item.key)) {
        continue;
      }
      safe[item.key] =
          item.value is num || item.value is bool || item.value == null
          ? item.value
          : redact(item.value.toString());
    }
    _entries.add({
      'time': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      ...safe,
    });
    _trim();
    notifyListeners();
    _flush ??= Timer(const Duration(milliseconds: 400), () {
      _flush = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    await ready;
    try {
      await _store.write({'version': 1, 'events': _entries});
    } on Object {
      storageError = 'Журнал не сохранён: проверьте свободное место';
    }
  }

  Future<void> clear() async {
    await ready;
    _entries.clear();
    await flush();
    notifyListeners();
  }

  Future<String> export() async {
    await flush();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 1,
      'platform': Platform.operatingSystem,
      'events': _entries,
    });
  }

  @override
  void dispose() {
    _flush?.cancel();
    super.dispose();
  }
}
