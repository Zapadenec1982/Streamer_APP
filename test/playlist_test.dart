import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/device/stations.dart';

/// Playlists in and out, as the web's stations.js reads and writes them.
void main() {
  test(
    'an .m3u: its #EXTINF names, the stream after each, comments skipped',
    () {
      final got = parsePlaylist(
        '#EXTM3U\r\n#EXTINF:-1,Radio Lantern\r\nhttp://a.invalid/1\r\n\r\n'
        '# a note\nhttp://a.invalid/2\n#EXTINF:0 tvg-id="x",  Northbound FM \nhttps://b.invalid/3\n',
      );
      expect(got, [
        (name: 'Radio Lantern', url: 'http://a.invalid/1'),
        (name: '', url: 'http://a.invalid/2'),
        (name: 'Northbound FM', url: 'https://b.invalid/3'),
      ]);
    },
  );

  test('a .pls: its File and Title lines by number', () {
    final got = parsePlaylist(
      '[playlist]\nNumberOfEntries=2\nFile1=http://a.invalid/1\nTitle1=Radio Lantern\n'
      'File2=http://a.invalid/2\nLength2=-1\nVersion=2\n',
    );
    expect(got, [
      (name: 'Radio Lantern', url: 'http://a.invalid/1'),
      (name: '', url: 'http://a.invalid/2'),
    ]);
    // in the order JavaScript's Object.keys gives: whole numbers ascending, then the rest as
    // they came
    final mixed = parsePlaylist(
      '[playlist]\nFile10=http://a.invalid/10\nFile02=http://a.invalid/02\n'
      'File2=http://a.invalid/2\nFile1=http://a.invalid/1\n',
    );
    expect(
      [for (final e in mixed) e.url.split('/').last],
      ['1', '2', '10', '02'],
    );
  });

  test('written as the web writes it, and read back the same', () {
    const stations = [
      Station(name: 'Radio Lantern', url: 'http://a.invalid/1'),
      Station(name: 'Нічне радіо', url: 'http://a.invalid/2', uuid: 'u2'),
    ];
    final text = toM3u(stations);
    expect(
      text,
      '#EXTM3U\n#EXTINF:-1,Radio Lantern\nhttp://a.invalid/1\n'
      '#EXTINF:-1,Нічне радіо\nhttp://a.invalid/2\n',
    );
    expect(parsePlaylist(text), [
      for (final s in stations) (name: s.name, url: s.url),
    ]);
  });

  test('imported: what the list can take, after the stations it has', () {
    const list = StationList(
      rev: 3,
      stations: [Station(name: 'Radio Lantern', url: 'http://a.invalid/1')],
      presets: [0, -1, -1, -1, -1, -1],
    );
    final got = importPlaylist(list, [
      (name: 'Again', url: 'http://a.invalid/1'),
      (name: '', url: 'https://b.invalid/live'),
      (name: 'Not a stream', url: 'ftp://c.invalid/x'),
    ]);
    expect(got.added, 1);
    expect(got.list.stations.map((s) => (s.name, s.url)), [
      ('Radio Lantern', 'http://a.invalid/1'),
      ('b.invalid', 'https://b.invalid/live'),
    ]);
    expect(got.list.presets, list.presets);
  });
}
