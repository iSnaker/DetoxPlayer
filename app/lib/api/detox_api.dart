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
    audioUrl: json['audio_url'] as String,
    coverUrl: json['cover_url'] as String,
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

  String get displayTitle => title.isNotEmpty ? title : filename;
  String get displayArtist =>
      artist.isNotEmpty ? artist : 'Неизвестный исполнитель';

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'folder': folder,
    'filename': filename,
    'duration': duration,
    'audio_url': audioUrl,
    'cover_url': coverUrl,
  };
}

class TrackPage {
  TrackPage(this.total, this.items);

  final int total;
  final List<Track> items;
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

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final http.Response response;
    try {
      response = await _client
          .get(resolve(path, query), headers: headers)
          .timeout(const Duration(seconds: 15));
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
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<String> deviceName() async {
    final data = await _getJson('/api/v1/me');
    return (data['device'] as Map<String, dynamic>)['name'] as String;
  }

  Future<TrackPage> tracks({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final data = await _getJson('/api/v1/tracks', {
      if (query.isNotEmpty) 'q': query,
      'offset': '$offset',
      'limit': '$limit',
    });
    final items = (data['items'] as List)
        .map((e) => Track.fromJson(e as Map<String, dynamic>))
        .toList();
    return TrackPage(data['total'] as int, items);
  }

  void close() => _client.close();
}
