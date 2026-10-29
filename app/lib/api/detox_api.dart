import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get unauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class Track {
  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.folder,
    required this.filename,
    required this.duration,
    required this.audioUrl,
    required this.coverUrl,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'].toString(),
    title: (json['title'] as String?)?.trim() ?? '',
    artist: (json['artist'] as String?)?.trim() ?? '',
    album: (json['album'] as String?)?.trim() ?? '',
    folder: (json['folder'] as String?) ?? '',
    filename: (json['filename'] as String?) ?? '',
    duration: (json['duration'] as num?)?.toDouble(),
    audioUrl:
        (json['audio_url'] as String?) ?? '/api/v1/tracks/${json['id']}/audio',
    coverUrl:
        (json['cover_url'] as String?) ?? '/api/v1/tracks/${json['id']}/cover',
  );

  final String id;
  final String title;
  final String artist;
  final String album;
  final String folder;
  final String filename;
  final double? duration;
  final String audioUrl;
  final String coverUrl;

  /// Position in the library listing; restores the original order after shuffle.
  int order = 0;

  late final String haystack = '$title $artist $album $folder $filename'
      .toLowerCase();

  String get displayTitle => title.isNotEmpty ? title : filename;
  String get displayArtist =>
      artist.isNotEmpty ? artist : 'Неизвестный исполнитель';
}

class DetoxApi {
  DetoxApi(String baseUrl, this.key, {http.Client? client})
    : baseUri = normalize(baseUrl),
      _client = client ?? http.Client();

  final Uri baseUri;
  final String key;
  final http.Client _client;

  Map<String, String> get headers => {'Authorization': 'Bearer $key'};

  static Uri normalize(String input) {
    var text = input.trim();
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.parse(text);
    if (uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ApiException('Некорректный адрес сервера');
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
  }

  Uri resolve(String path, [Map<String, String>? query]) {
    final uri = baseUri.resolve(path);
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<http.Response> _get(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final http.Response response;
    try {
      response = await _client
          .get(resolve(path, query), headers: headers)
          .timeout(timeout);
    } on Exception {
      throw ApiException('Не удалось подключиться к серверу');
    }
    if (response.statusCode == 401) {
      throw ApiException('Ключ недействителен или отозван', statusCode: 401);
    }
    if (response.statusCode == 429) {
      throw ApiException(
        'Слишком много попыток, подождите минуту',
        statusCode: 429,
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        'Ошибка сервера (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await _get(path);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<String> deviceName() async {
    final data = await _getJson('/api/v1/me');
    return (data['device'] as Map<String, dynamic>)['name'] as String;
  }

  Future<String> libraryVersion() async {
    final data = await _getJson('/api/v1/library/version');
    return data['version'] as String;
  }

  Future<String> libraryExport() async {
    final response = await _get(
      '/api/v1/library/export',
      timeout: const Duration(seconds: 90),
    );
    return utf8.decode(response.bodyBytes);
  }

  void close() => _client.close();
}
