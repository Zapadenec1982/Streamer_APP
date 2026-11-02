import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/media.dart';

/// The library's and the DLNA browser's helpers, on the cases tools/tests/test_webui_media.py
/// holds the web's media.js to.
void main() {
  test('commands pack as dlna_client::encode() packs them', () {
    for (final (command, row, revision) in [
      (2, 0, 1),
      (2, 11, 4097),
      (3, 0, 65535),
      (6, 255, 65534),
      (7, 300, 12),
    ]) {
      final got = browseCode(command, row, revision);
      expect(got, (revision & 0xffff) << 12 | (row & 255) << 4 | command);
      expect(got, lessThanOrEqualTo(268435455));
    }
  });

  test('rows are named as on the panel', () {
    const cases = {
      'Artist/Album/01 - Title.flac': ('01 - Title', 'Artist/Album'),
      'Mr. Brown': ('Mr. Brown', ''),
      'Mr. Brown.mp3': ('Mr. Brown', ''),
      'a/.hidden': ('.hidden', 'a'),
      'a/b.c': ('b.c', 'a'),
      'a/song.opus': ('song', 'a'),
      'a/song.mpeg4': ('song.mpeg4', 'a'),
      'a/song.m-4': ('song.m-4', 'a'),
    };
    for (final MapEntry(key: path, value: (name, folder)) in cases.entries) {
      expect(
        (trackName(path), trackFolder(path)),
        (name, folder),
        reason: path,
      );
    }
  });

  test('the path to play is Playlist::path_at()\'s', () {
    expect(trackPath('/sdcard', 'A/b.flac'), '/sdcard/A/b.flac');
  });

  test('the filter takes every word, in any case', () {
    const p = 'ДахаБраха/Шлях/03 - Вівця.flac';
    expect(
      [
        matchesFilter(p, ''),
        matchesFilter(p, 'шлях'),
        matchesFilter(p, 'ДАХА вівця'),
        matchesFilter(p, 'даха 04'),
        matchesFilter(p, '  '),
        matchesFilter(p, 'flac'),
      ],
      [true, true, true, false, true, true],
    );
  });

  test('the crumbs follow the snapshots', () {
    ({String title, bool servers}) v(String title, [bool servers = false]) =>
        (title: title, servers: servers);
    final out = <List<String?>>[];
    var c = <String?>[];
    c = nextCrumbs(c, const Opened('NAS'), v('NAS'));
    out.add(c);
    c = nextCrumbs(c, const Opened('CD1'), v('CD1'));
    out.add(c);
    // a folder named like its parent
    c = nextCrumbs(c, const Opened('CD1'), v('CD1'));
    out.add(c);
    // the next page: the same folder
    c = nextCrumbs(c, null, v('CD1'));
    out.add(c);
    c = nextCrumbs(c, const WentBack(), v('CD1'));
    out.add(c);
    // the open failed: nothing moved
    c = nextCrumbs(c, const Opened('X'), v('CD1'));
    out.add(c);
    // the panel went somewhere
    c = nextCrumbs(c, null, v('Elsewhere'));
    out.add(c);
    // climbing a path not seen
    c = nextCrumbs(c, const WentBack(), v('Up'));
    out.add(c);
    c = nextCrumbs(c, const WentBack(), v('Media', true));
    out.add(c);
    expect(out, [
      ['NAS'],
      ['NAS', 'CD1'],
      ['NAS', 'CD1', 'CD1'],
      ['NAS', 'CD1', 'CD1'],
      ['NAS', 'CD1'],
      ['NAS', 'CD1'],
      [null, 'Elsewhere'],
      [null, 'Up'],
      <String?>[],
    ]);
  });
}
