import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/device/stations.dart';

/// The list's edits, as the web's lib/stations.js makes them: the presets follow their stations.
void main() {
  const list = StationList(
    rev: 7,
    stations: [
      Station(name: 'A', url: 'http://a.invalid/1'),
      Station(name: 'B', url: 'http://b.invalid/2', uuid: 'u-b'),
      Station(name: 'C', url: 'http://c.invalid/3'),
    ],
    presets: [0, 2, -1, 1, -1, -1],
  );
  List<String> names(StationList l) => [for (final s in l.stations) s.name];

  test('a removed station leaves its preset; the later ones move up', () {
    final out = list.remove(1);
    expect(names(out), ['A', 'C']);
    expect(out.presets, [0, 1, -1, -1, -1, -1]);
    expect(out.rev, 7, reason: 'the generation it was made from');
  });

  test('a moved station takes its presets along', () {
    final up = list.move(2, 0);
    expect(names(up), ['C', 'A', 'B']);
    expect(up.presets, [1, 0, -1, 2, -1, -1]);
    expect(identical(list.move(0, -1), list), isTrue);
  });

  test('a name is cut to 63 bytes at a character', () {
    final long = 'Ї' * 40; // 80 bytes
    final out = list.rename(0, long);
    expect(utf8.encode(out.stations[0].name).length, lessThanOrEqualTo(63));
    expect(out.stations[0].name, 'Ї' * 31);
  });

  test('a preset holds one station; −1 takes it off them all', () {
    expect(list.setPreset(2, 3).presets, [0, 2, -1, 2, -1, -1]);
    expect(list.setPreset(2, -1).presets, [0, -1, -1, 1, -1, -1]);
  });

  test('a stream is refused for what the panel cannot keep', () {
    expect(list.refuse('ftp://x'), Refusal.url);
    expect(list.refuse('https://x.invalid/${'a' * 230}'), Refusal.urlLong);
    expect(list.refuse('http://b.invalid/2'), Refusal.duplicate);
    final full = StationList(
      rev: 1,
      stations: [
        for (var i = 0; i < 64; i++) Station(name: '$i', url: 'http://s/$i'),
      ],
      presets: const [-1, -1, -1, -1, -1, -1],
    );
    expect(full.refuse('http://new.invalid/'), Refusal.full);
    expect(list.refuse('https://new.invalid/live'), isNull);
  });

  test('a stream without a name goes by its host', () {
    expect(
      list.add('', 'https://radio.invalid:8000/live').stations.last.name,
      'radio.invalid:8000',
    );
  });

  test(
    'the body puts the generation first and a uuid only where there is one',
    () {
      final body = list.toJson();
      expect(body.keys.first, 'rev');
      expect(jsonEncode(body['stations']), contains('"uuid":"u-b"'));
      expect((body['stations']! as List).first, {
        'name': 'A',
        'url': 'http://a.invalid/1',
      });
    },
  );
}
