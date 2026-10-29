import 'dart:convert';

import 'package:detox_player/api/detox_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('normalize adds scheme and strips path', () {
    expect(
      DetoxApi.normalize('192.168.1.5:8081/x').toString(),
      'http://192.168.1.5:8081',
    );
    expect(
      () => DetoxApi.normalize('ftp://host'),
      throwsA(isA<ApiException>()),
    );
  });

  test('library requests send the bearer key', () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      final body = request.url.path.endsWith('version')
          ? {'version': 'v1', 'total': 1}
          : {'version': 'v1', 'total': 0, 'items': []};
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });
    final api = DetoxApi('http://x:8081', 'secret', client: client);
    expect(await api.libraryVersion(), 'v1');
    expect(await api.libraryExport(), contains('"version":"v1"'));
    expect(seen.map((r) => r.url.path), [
      '/api/v1/library/version',
      '/api/v1/library/export',
    ]);
    expect(seen.every((r) => r.headers['Authorization'] != null), isTrue);
  });

  test('401 is reported as unauthorized', () async {
    final api = DetoxApi(
      'http://x',
      'k',
      client: MockClient((_) async => http.Response('', 401)),
    );
    expect(
      api.deviceName(),
      throwsA(predicate((e) => e is ApiException && e.unauthorized)),
    );
  });
}
