import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/media.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/device/panel/endpoint.dart';
import 'package:streamer/device/panel/panel_device_api.dart';
import 'package:streamer/device/panel/panel_link.dart';

import 'support/fake_panel.dart';

/// The card's library, the media servers and the queue against a panel on the loopback: what goes
/// to it, in the shape the firmware reads.
void main() {
  late FakePanel panel;
  late PanelDeviceApi api;

  setUp(() async {
    panel = FakePanel({
      'audio.source': 4,
      'audio.sources': 249,
      'audio.transport_caps': 254,
      'player.state': 'playing',
      'player.title': 'Glasshouse',
      'player.pos_s': 12,
      'player.dur_s': 234,
      'player.repeat': 0,
      'player.shuffle': false,
      'player.index': 2,
      'player.count': 250,
    });
    panel.library = [for (var i = 0; i < 250; i++) 'Artist/Album/$i.flac'];
    await panel.start();
    api = PanelDeviceApi(
      PanelLink(
        PanelEndpoint('127.0.0.1', port: panel.port),
        timeout: const Duration(seconds: 2),
      ),
    );
    await until(() => api.current.known);
  });

  tearDown(() async {
    api.dispose();
    await panel.close();
  });

  Map<String, Object?> lastBody() =>
      (panel.requests.lastWhere((r) => r.method == 'POST').body! as Map)
          .cast<String, Object?>();

  test('the card\'s queue on the Player: seekable, its modes, where it is', () {
    final now = api.current.now;
    expect(now.kind, NowKind.card);
    expect(now.seekable, isTrue);
    expect(now.repeat, 0);
    expect(now.shuffle, isFalse);
    expect(api.current.cardIndex, 2);
    expect(api.current.cardCount, 250);
  });

  test('the library comes a page at a time', () async {
    final first = await api.library();
    expect(first.count, 250);
    expect(first.rows, hasLength(200));
    expect(first.root, '/sdcard');
    final rest = await api.library(from: 200);
    expect(rest.rows, hasLength(50));
    expect(rest.rows.first, 'Artist/Album/200.flac');
  });

  test('a track plays by its path, then the command, in one body', () async {
    await api.playTrack(trackPath('/sdcard', 'Artist/Album/7.flac'));
    final body = lastBody();
    expect(body.keys.toList(), ['player.track', 'player.cmd']);
    expect(body['player.track'], '/sdcard/Artist/Album/7.flac');
    expect(body['player.cmd'], 1);
  });

  test('seek, repeat and shuffle write the card\'s keys', () async {
    await api.seek(95);
    expect(lastBody(), {'player.seek_s': 95});
    await api.setRepeat(2);
    expect(lastBody(), {'player.repeat': 2});
    await api.setShuffle(true);
    expect(lastBody(), {'player.shuffle': true});
  });

  test(
    'the media servers: the snapshot as the app\'s model, a command packed',
    () async {
      panel.dlna = {
        'revision': 9,
        'busy': false,
        'servers': false,
        'can_back': true,
        'count': 2,
        'next': true,
        'previous': false,
        'title': 'CD1',
        'status': '@dlna.st_page\u001fn=2',
        'rows': [
          {'title': 'Disc', 'artist': '', 'folder': true, 'playable': false},
          {
            'title': 'Song',
            'artist': 'Band',
            'folder': false,
            'playable': true,
          },
        ],
      };
      final view = await api.dlnaView();
      expect(view.revision, 9);
      expect(view.servers, isFalse);
      expect(view.next, isTrue);
      expect(view.rows.map((r) => (r.title, r.folder, r.playable)), [
        ('Disc', true, false),
        ('Song', false, true),
      ]);
      await api.dlnaCommand(browseCode(Browse.open, 1, view.revision));
      expect(lastBody(), {'dlna.browse_cmd': 9 << 12 | 1 << 4 | Browse.open});
    },
  );
}
