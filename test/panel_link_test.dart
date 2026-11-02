import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/device/panel/endpoint.dart';
import 'package:streamer/device/panel/panel_device_api.dart';
import 'package:streamer/device/panel/panel_link.dart';

import 'support/fake_panel.dart';

/// The app against a panel on the loopback: plain tests, no widgets, so the real network stack
/// (a widget test would put a fake HttpClient in its place).
void main() {
  const bt = {
    'audio.source': 3,
    'audio.sources': 249,
    'audio.volume': 32,
    'audio.mute': false,
    'audio.transport_caps': 126,
    'bt.peer': 'Phone',
    'bt.title': 'Amber Hours',
    'bt.artist': 'Lantern Theory',
    'bt.play_state': 'playing',
    'bt.codec': 'LHDC V5',
    'bt.rate_hz': 96000,
    'bt.pos_s': 56,
    'bt.dur_s': 222,
    'airplay.name': 'ModESP',
    'ui.theme': 2,
    'system.mdns_hostname': 'modesp-2c4c',
  };

  late FakePanel panel;
  late PanelLink link;

  setUp(() async {
    panel = FakePanel(bt);
    await panel.start();
    link = PanelLink(
      PanelEndpoint('127.0.0.1', port: panel.port),
      backoff: const [Duration(milliseconds: 20)],
      busyRetry: const Duration(milliseconds: 50),
      silence: const Duration(milliseconds: 200),
      timeout: const Duration(seconds: 2),
    );
  });

  tearDown(() async {
    await link.dispose();
    await panel.close();
  });

  test('hears the whole state first, then what changes; service keys are not state', () async {
    link.start();
    await until(() => link.known);
    expect(link.status, LinkStatus.ready);
    expect(link.state['bt.title'], 'Amber Hours');
    panel.change({'bt.title': 'Tidewater Static'});
    panel.heartbeat();
    await until(() => link.state['bt.title'] == 'Tidewater Static');
    expect(link.state.keys.where((k) => k.startsWith('_')), isEmpty);
  });

  test('the snapshot becomes the app\'s models', () async {
    final api = PanelDeviceApi(link);
    await until(() => api.current.known);
    final s = api.current;
    expect(s.name, 'ModESP');
    expect(s.scheme, 2);
    expect(s.volume, 32);
    expect(s.now.kind, NowKind.bt);
    expect((s.now.title as TextLabel).text, 'Amber Hours');
    expect(s.now.device, 'Phone');
    expect(s.now.canToggle && s.now.canPrevious && s.now.canNext, isTrue);
    expect(s.now.duration, const Duration(seconds: 222));
    expect(s.cards.map((c) => c.card), [
      SourceCard.bt,
      SourceCard.airplay,
      SourceCard.radio,
      SourceCard.card,
      SourceCard.servers,
      SourceCard.usb,
    ]);
    expect(s.cards.first.active, isTrue);
    expect((s.cards.first.status as TextLabel).text, 'Amber Hours');
  });

  test('a write goes as JSON and comes back as the panel\'s state', () async {
    final api = PanelDeviceApi(link);
    await until(() => api.current.known);
    await api.setVolume(55);
    expect(panel.requests.last.contentType, 'application/json');
    expect(panel.requests.last.body, {'audio.volume': 55});
    await until(() => api.current.volume == 55);
  });

  test(
    'transport goes only where the panel says the source takes it',
    () async {
      final api = PanelDeviceApi(link);
      await until(() => api.current.known);
      await api.transport(TransportAction.toggle);
      expect(panel.requests.last.body, {'audio.transport': 6});
      await until(() => !api.current.now.playing);
      panel.change({'audio.transport_caps': 0});
      await until(() => !api.current.now.canToggle);
      final before = panel.requests.length;
      await api.transport(TransportAction.next);
      expect(panel.requests.length, before);
    },
  );

  test('choosing the radio also starts it', () async {
    final api = PanelDeviceApi(link);
    await until(() => api.current.known);
    await api.selectSource(SourceId.radio);
    expect(panel.requests.last.body, {'audio.source': 5, 'radio.cmd': 1});
  });

  test(
    'a refused write is a PanelError; with the login it goes through',
    () async {
      panel.password = 'secret';
      await expectLater(
        link.write({'audio.volume': 10}),
        throwsA(
          isA<PanelError>().having(
            (e) => e.unauthorized,
            'unauthorized',
            isTrue,
          ),
        ),
      );
      link.endpoint = link.endpoint.withLogin('admin', 'secret');
      await link.write({'audio.volume': 10});
      expect(panel.state['audio.volume'], 10);
    },
  );

  test('a busy panel is shown as busy and tried again', () async {
    panel.busy = true;
    link.start();
    await until(() => link.status == LinkStatus.busy);
    panel.busy = false;
    await until(() => link.status == LinkStatus.ready);
  });

  test('a dropped socket comes back with a fresh snapshot', () async {
    link.start();
    await until(() => link.known);
    panel.state['audio.volume'] = 12;
    await panel.dropAll();
    await until(() => panel.clients == 1 && link.state['audio.volume'] == 12);
    expect(link.status, LinkStatus.ready);
  });

  test(
    'silence after a heartbeat ends the socket, and a new one is taken',
    () async {
      link.start();
      await until(() => link.known);
      panel.heartbeat();
      final before = panel.connections;
      await until(
        () => panel.connections > before && link.status == LinkStatus.ready,
      );
    },
  );

  test('stop lets go of the socket; start takes one again', () async {
    link.start();
    await until(() => panel.clients == 1);
    await link.stop();
    await until(() => panel.clients == 0);
    link.start();
    await until(() => panel.clients == 1);
  });

  test(
    'suspend lets go of the panel; resume hears it again from the whole state',
    () async {
      final api = PanelDeviceApi(link);
      await until(() => panel.clients == 1 && api.current.known);
      api.suspend();
      await until(() => panel.clients == 0);
      panel.state['audio.volume'] = 70;
      api.resume();
      await until(() => panel.clients == 1 && api.current.volume == 70);
    },
  );

  test('the cover is fetched once per picture, and a 404 means none', () async {
    final api = PanelDeviceApi(link);
    expect(await api.cover('1'), isNull);
    panel.cover = Uint8List.fromList([1, 2, 3]);
    expect(await api.cover('2'), [1, 2, 3]);
    final asked = panel.requests.length;
    expect(await api.cover('2'), [1, 2, 3]);
    expect(
      panel.requests.length,
      asked,
      reason: 'the same picture is not asked for again',
    );
    // another ui.cover with the same picture: the panel answers 304 to the ETag kept
    expect(await api.cover('3'), [1, 2, 3]);
    panel.cover = null;
    expect(await api.cover('4'), isNull);
  });

  test(
    'a sound is chosen on the panel\'s version even when it moved meanwhile',
    () async {
      final api = PanelDeviceApi(link);
      final presets = await api.soundPresets();
      expect(presets.preset, 'rock');
      expect(presets.presets, ['custom', 'flat', 'pop', 'rock']);
      panel.eqConflict = true;
      await api.chooseSound('pop');
      expect(panel.eqPreset, 'pop');
      await api.keepSound();
      expect(panel.eqKeeps, 1);
    },
  );

  test('the station list: a preset naming no station is empty', () async {
    final api = PanelDeviceApi(link);
    final list = await api.stations();
    expect(list.stations.map((s) => s.name), [
      'Radio Lantern',
      'Northbound FM',
    ]);
    expect(list.presets, [1, 0, -1, -1, -1, -1]);
  });

  test('what plays goes onto a preset by the catalog\'s keys, its name cut to 63 bytes', () async {
    final long = 'Радіо ${'Ж' * 40}';
    panel.state
      ..['audio.source'] = 5
      ..['radio.station'] = -1
      ..['radio.name'] = long
      ..['radio.url'] = 'http://a.invalid/x'
      ..['radio.uuid'] = 'u9';
    final api = PanelDeviceApi(link);
    await until(() => api.current.known);
    expect(api.current.radio.keepable, isTrue);
    await api.storePreset(2);
    final body = (panel.requests.last.body! as Map).cast<String, Object?>();
    final name = body['radio.web_name']! as String;
    expect(utf8.encode(name).length, lessThanOrEqualTo(63));
    expect(long.startsWith(name), isTrue);
    expect(body['radio.web_url'], 'http://a.invalid/x');
    expect(body['radio.web_uuid'], 'u9');
    expect(body['radio.web_act'], 4);
    expect(body['radio.fav_add'], true);
  });

  test(
    'listen tunes another station, or plays the tuned one when it is off',
    () async {
      panel.state
        ..['audio.source'] = 5
        ..['radio.station'] = 0
        ..['radio.state'] = 'idle'
        ..['radio.name'] = 'Radio Lantern';
      final api = PanelDeviceApi(link);
      await until(() => api.current.known);
      await api.listen(1);
      expect(panel.requests.last.body, {'radio.station': 1});
      panel.change({'radio.station': 0});
      await until(() => api.current.radio.current == 0);
      await api.listen(0);
      expect(panel.requests.last.body, {'radio.cmd': 1});
    },
  );

  test('the loudness comes back at the strength the panel kept', () async {
    panel.state['audio.loud_back'] = 60;
    final api = PanelDeviceApi(link);
    await until(() => api.current.known);
    await api.setLoudness(true);
    expect(panel.requests.last.body, {'audio.loudness': 60});
    await api.setLoudness(false);
    expect(panel.requests.last.body, {'audio.loudness': 0});
  });

  test('an address as a person types it', () {
    expect(PanelEndpoint.parse(' 192.168.1.216 ')?.host, '192.168.1.216');
    expect(PanelEndpoint.parse('modesp-2c4c.local')?.port, 80);
    expect(PanelEndpoint.parse('panel:8080')?.port, 8080);
    expect(PanelEndpoint.parse('http://panel/')?.host, 'panel');
    expect(PanelEndpoint.parse(''), isNull);
  });
}
