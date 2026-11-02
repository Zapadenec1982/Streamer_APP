import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/radio_browser.dart';

/// The catalogue client against a Radio Browser on the loopback: the panel's rules for what is
/// kept, one row per stream, and each logo asked once.
void main() {
  late HttpServer server;
  late RadioBrowser rb;
  final asked = <Uri>[];
  Object? reply(Uri uri) => switch (uri.path) {
    '/json/stations/search' => [
      {
        'name': 'Kept',
        'url_resolved': 'https://a.invalid/x?y=1',
        'codec': 'MP3',
        'bitrate': 192,
        'stationuuid': 'k',
      },
      {
        'name': 'Same stream',
        'url_resolved': 'https://a.invalid/x?y=2',
        'codec': 'MP3',
        'bitrate': 192,
      },
      {
        'name': 'Low',
        'url_resolved': 'https://b.invalid/',
        'codec': 'MP3',
        'bitrate': 64,
      },
      {
        'name': 'HLS',
        'url_resolved': 'https://c.invalid/',
        'codec': 'AAC',
        'bitrate': 256,
        'hls': 1,
      },
      {
        'name': 'Ogg',
        'url_resolved': 'https://d.invalid/',
        'codec': 'OGG',
        'bitrate': 256,
      },
      {
        'name': ' ',
        'url_resolved': 'https://e.invalid/',
        'codec': 'AAC+',
        'bitrate': 128,
      },
      {
        'name': 'Lossless',
        'url_resolved': 'https://f.invalid/',
        'codec': 'FLAC',
        'bitrate': 0,
      },
    ],
    '/json/countrycodes' => [
      {'name': 'de', 'stationcount': 10},
      {'name': 'UA', 'stationcount': 3},
      {'name': 'DE', 'stationcount': 5},
      {'name': 'XYZ', 'stationcount': 9},
    ],
    '/json/stations/byuuid' => [
      for (final u in uri.queryParameters['uuids']!.split(','))
        {
          'stationuuid': u,
          'favicon': u.startsWith('0') ? 'https://logo.invalid/$u.png' : '',
        },
    ],
    _ => null,
  };

  setUp(() async {
    asked.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      asked.add(req.uri);
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(reply(req.uri)));
      req.response.close();
    });
    rb = RadioBrowser(base: 'http://127.0.0.1:${server.port}');
  });
  tearDown(() async {
    rb.close();
    await server.close(force: true);
  });

  test(
    'what the panel can play, above the floor, one row per stream',
    () async {
      final page = await rb.stations(const ByTag('jazz'), uaOnly: true);
      expect(
        [for (final r in page.rows) r.name],
        ['Kept', 'https://e.invalid/'],
      );
      expect(page.more, isFalse);
      final q = asked.single.queryParameters;
      expect(q['tag'], 'jazz');
      expect(q['countrycode'], 'UA');
      expect(q['bitrateMin'], '128');
      expect(q['order'], 'clickcount');
      final flac = await rb.stations(
        const ByName('x'),
        floor: CatalogFloor.flac,
      );
      expect([for (final r in flac.rows) r.name], ['Lossless']);
    },
  );

  test('the countries: one per code, Ukraine first, then by count', () async {
    expect(await rb.countries(), [
      (code: 'UA', count: 3),
      (code: 'DE', count: 15),
    ]);
  });

  test('a logo is asked once; a malformed uuid never', () async {
    const a = '00000000-0000-0000-0000-000000000001';
    const b = '10000000-0000-0000-0000-000000000002';
    expect(await rb.favicons([a, b, 'bad']), {
      a: 'https://logo.invalid/$a.png',
      b: '',
    });
    expect(await rb.favicons([a]), {a: 'https://logo.invalid/$a.png'});
    expect(asked.where((u) => u.path == '/json/stations/byuuid'), hasLength(1));
  });
}
