import 'dart:convert';

import 'package:detox_player/api/detox_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('normalize adds scheme and strips path', () {
    expect(DetoxApi.normalize('192.168.1.5:8081/x').toString(), 'http://192.168.1.5:8081');
    expect(() => DetoxApi.normalize('ftp://host'), throwsA(isA<ApiException>()));
  });

  test('tracks sends bearer key and parses Russian fields', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'total': 1,
          'items': [
            {
              'id': 7,
              'title': '',
              'artist': null,
              'album': 'Как Люди',
              'folder': 'a',
              'filename': '01.mp3',
              'duration': 12.5,
              'audio_url': '/api/v1/tracks/7/audio',
              'cover_url': '/api/v1/tracks/7/cover',
            }
          ],
        })),
        200,
      );
    });
    final api = DetoxApi('http://x:8081', 'secret', client: client);
    final page = await api.tracks(query: 'люди');
    expect(seen.headers['Authorization'], 'Bearer secret');
    expect(seen.url.queryParameters['q'], 'люди');
    expect(page.items.single.displayTitle, '01.mp3');
    expect(page.items.single.displayArtist, 'Неизвестный исполнитель');
  });

  test('401 is reported as unauthorized', () async {
    final api = DetoxApi('http://x', 'k', client: MockClient((_) async => http.Response('', 401)));
    expect(api.deviceName(), throwsA(predicate((e) => e is ApiException && e.unauthorized)));
  });
}
