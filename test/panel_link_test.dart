import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/eq.dart';
import 'package:streamer/device/streamer.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/device/panel/endpoint.dart';
import 'package:streamer/device/panel/panel_device_api.dart';
import 'package:streamer/device/panel/panel_link.dart';

import 'support/fake_panel.dart';
import 'support/images.dart';

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
      final presets = await api.eq();
      expect(presets.preset, 'rock');
      expect(presets.presets, ['custom', 'flat', 'pop', 'rock']);
      panel.eqConflict = true;
      await api.chooseSound('pop');
      expect(panel.eqPreset, 'pop');
      await api.keepSound();
      expect(panel.eqKeeps, 1);
    },
  );

  test('the EQ document with its bands; an edit of them goes from its '
      'revision, and the glass\'s change meanwhile is a conflict', () async {
    final api = PanelDeviceApi(link);
    final doc = await api.eq();
    expect(doc.fs, 48000);
    expect(doc.bands, const [
      EqBand(type: EqType.lowshelf, f: 40, gain: 4.9, q: 0.707),
      EqBand(type: EqType.peak, f: 62.5, gain: 3.6),
      EqBand(type: EqType.peak, f: 125, on: false),
    ]);
    final edited = [doc.bands.first.copyWith(gain: -2), ...doc.bands.skip(1)];
    final rev = await api.setEqBands(doc.rev, edited);
    expect(rev, doc.rev + 1);
    final body = (panel.requests.last.body! as Map).cast<String, Object?>();
    expect(body.keys.first, 'rev', reason: 'the panel reads it off the front');
    expect((body['bands']! as List).first, {
      'type': 'lowshelf',
      'f': 40.0,
      'gain': -2.0,
      'q': 0.707,
      'on': true,
    });
    expect(panel.eqPreset, 'custom');
    // the glass moved it: the old revision is refused
    await expectLater(
      api.setEqBands(doc.rev, edited),
      throwsA(isA<EqChanged>()),
    );
  });

  test('the volume\'s two and the leveler\'s schedule go as settings, held '
      'to the panel\'s ranges', () async {
    final api = PanelDeviceApi(link);
    Map<String, Object?> last() =>
        (panel.requests.last.body! as Map).cast<String, Object?>();
    await api.setVolMax(105);
    expect(last(), {'audio.vol_max': 100});
    await api.setVolStart(30);
    expect(last(), {'audio.vol_start': 30});
    await api.setLevelerSchedule(on: true);
    expect(last(), {'audio.lev_sched': true});
    await api.setLevelerSchedule(from: 1320, to: 2000);
    expect(last(), {'audio.lev_from': 1320, 'audio.lev_to': 1435});
  });

  test('the sound\'s state: the volume\'s two, the schedule, and the port '
      'that plays — none for closed speakers', () {
    final s = snapshotOf({
      'audio.vol_max': 85,
      'audio.vol_start': 30,
      'audio.lev_sched': true,
      'audio.lev_from': 1380,
      'audio.lev_to': 360,
      'audio.loud_db': 4.5,
      'audio.hp_hz': 30,
      'audio.spk_type': 1,
      'audio.port_hz': 45,
      'audio.port_lift_db': 2,
    }).sound;
    expect(s.volMax, 85);
    expect(s.volStart, 30);
    expect(s.levSchedule, isTrue);
    expect((s.levFrom, s.levTo), (1380, 360));
    expect(s.loudDb, 4.5);
    expect((s.hpHz, s.portHz, s.portLiftDb), (30, 45, 2));
    expect(
      snapshotOf({'audio.spk_type': 2, 'audio.port_hz': 45}).sound.portHz,
      0,
    );
    final old = snapshotOf(const {}).sound;
    expect((old.volMax, old.volStart, old.levSchedule), (null, null, null));
  });

  test('Wi-Fi, the clock and Bluetooth go to their routes in the bodies the '
      'streamer reads', () async {
    final api = PanelDeviceApi(link);
    Map<String, Object?> last() =>
        (panel.requests.last.body! as Map).cast<String, Object?>();
    expect(
      [for (final n in (await api.wifiScan())!) n.ssid],
      ['Lantern Home', 'Northbound Guest'],
    );
    await api.wifiJoin('Lantern Home', 'secret-pass');
    expect(last(), {
      'ssid': 'Lantern Home',
      'password': 'secret-pass',
      'join': true,
    });
    panel.refuseNext = (409, {'error': 'busy'});
    await expectLater(
      api.wifiJoin('Lantern Home', 'secret-pass'),
      throwsA(isA<PanelError>().having((e) => e.code, 'code', 'busy')),
    );
    await api.wifiForget();
    expect(last(), {'forget': true});
    expect((await api.wifiAp()).ssid, 'ModESP-2C4C');
    await api.setWifiAp('Lantern AP', 'appass123', 20);
    expect(last(), {
      'ssid': 'Lantern AP',
      'password': 'appass123',
      'channel': 13,
    });
    expect((await api.panelTime()).timezone, 'EET-2EEST,M3.5.0/3,M10.5.0/4');
    await api.setPanelTime(
      ntp: false,
      timezone: 'CET-1CEST,M3.5.0,M10.5.0/3',
      unix: 1793662860,
    );
    expect(last(), {
      'mode': 'manual',
      'timezone': 'CET-1CEST,M3.5.0,M10.5.0/3',
      'time': 1793662860,
    });
    await api.setPanelTime(ntp: true, timezone: 'UTC12');
    expect(last(), {'mode': 'ntp', 'timezone': 'UTC12'});
    expect((await api.bt()).name, 'MODEsp');
    await api.btSet(discoverable: true, codecs: 3);
    expect(last(), {'discoverable': true, 'codecs': 3});
    await api.btSet(name: 'Kitchen');
    expect(last(), {'name': 'Kitchen'});
    await api.btForget('all');
    expect(last(), {'forget': 'all'});
    await api.btDisconnect();
    expect(last(), {'disconnect': true});
    panel.refuseNext = (409, {'error': 'answered', 'by': 1});
    await expectLater(
      api.btPair(accept: true, seq: 4),
      throwsA(
        isA<PanelError>()
            .having((e) => e.code, 'code', 'answered')
            .having((e) => e.body?['by'], 'by', 1),
      ),
    );
    expect(last(), {'pair': 'accept', 'seq': 4});
    await api.restart();
    expect(panel.restarts, 1);
  });

  test('the login, the firmware and the backups go to their routes as the '
      'streamer takes them', () async {
    final api = PanelDeviceApi(link);
    Map<String, Object?> last() =>
        (panel.requests.last.body! as Map).cast<String, Object?>();
    Matcher refused(String code) =>
        throwsA(isA<PanelError>().having((e) => e.code, 'code', code));
    panel.password = 'modesp';
    // the login is read without one; changed only with it
    expect((await api.auth()).enabled, isTrue);
    await expectLater(
      api.setAuth(username: 'kitchen'),
      throwsA(isA<PanelError>().having((e) => e.unauthorized, '401', isTrue)),
    );
    link.endpoint = link.endpoint.withLogin('admin', 'modesp');
    await expectLater(
      api.setAuth(currentPassword: 'nope', newPassword: 'lantern42'),
      refused('wrong_password'),
    );
    expect(last(), {'current_pass': 'nope', 'new_pass': 'lantern42'});
    await api.setAuth(
      username: 'kitchen',
      currentPassword: 'modesp',
      newPassword: 'lantern42',
    );
    expect(last(), {
      'username': 'kitchen',
      'current_pass': 'modesp',
      'new_pass': 'lantern42',
    });
    expect((panel.user, panel.password), ('kitchen', 'lantern42'));
    link.endpoint = link.endpoint.withLogin('kitchen', 'lantern42');
    await api.setAuth(enabled: false);
    expect(last(), {'enabled': false});
    expect(panel.password, isNull);
    expect((await api.auth()).username, 'kitchen');

    // the firmware: raw bytes with their length, the pieces followed
    final info = await api.otaInfo();
    expect(
      (info.board, info.partition, info.version),
      ('modesp_p4_player', 'ota_0', '0.1.0'),
    );
    final sent = <double>[];
    await api.otaUpload(
      appImage('modesp_p4_player', size: 40000),
      progress: sent.add,
    );
    expect(panel.otaImage, hasLength(40000));
    expect(panel.requests.last.contentType, 'application/octet-stream');
    expect(sent, [16384 / 40000, 32768 / 40000, 1.0]);
    await expectLater(
      api.otaUpload(appImage('modesp_c6_bridge')),
      throwsA(
        isA<PanelError>()
            .having((e) => e.code, 'code', 'board_mismatch')
            .having((e) => e.body?['incoming'], 'incoming', 'modesp_c6_bridge')
            .having((e) => e.body?['running'], 'running', 'modesp_p4_player'),
      ),
    );

    // the person's files: staged; one the streamer cannot read refuses them all
    final files = await api.userFiles();
    expect(files['modesp_userdata'], 1);
    expect(await api.restoreUserFiles(files), 2);
    expect(panel.restoredFiles, files);
    panel.badFile = 'eq.json';
    await expectLater(
      api.restoreUserFiles(files),
      throwsA(
        isA<PanelError>()
            .having((e) => e.code, 'code', 'bad_file')
            .having((e) => e.body?['file'], 'file', 'eq.json'),
      ),
    );
    final settings = await api.settingsBackup();
    expect(settings['modesp_backup'], 1);
    await api.restoreSettings(settings);
    expect(panel.restoredSettings, settings);
  });

  test('the streamer\'s own settings in a snapshot', () {
    final s = snapshotOf({
      'ui.backlight': 60,
      'ui.standby_min': 15,
      'ui.lang': 2,
      'airplay.enabled': true,
      'airplay.mode': 1,
      'airplay.switching': true,
      'airplay.mode_status': '@airplay.st_switching',
      'dlna.enabled': false,
      'bt.link': true,
      'bt.peer': 'Phone',
      'bt.cfg_rev': 9,
      'bt.pair_seq': 3,
      'bt.pair_active': true,
      'bt.pair_kind': 1,
      'bt.pair_name': 'Tablet',
      'wifi.mode': 'sta',
      'wifi.connected': true,
      'wifi.ssid': 'Lantern Home',
      'wifi.ip': '192.168.1.47',
      'wifi.try': 'fail',
      'wifi.reason': 202,
      'system.time': '23:41',
    }).streamer;
    expect((s.backlight, s.sleepMinutes, s.language), (60, 15, 2));
    expect((s.airplay, s.airplayMode, s.airplaySwitching), (true, 1, true));
    expect((s.dlna, s.covers), (false, null));
    expect((s.btLink, s.btPeer, s.btConfigRev), (true, 'Phone', 9));
    expect(
      (s.pairing.seq, s.pairing.active, s.pairing.kind, s.pairing.name),
      (3, true, PairKind.consent, 'Tablet'),
    );
    expect(s.wifi.network, 'Lantern Home');
    expect((s.wifi.tryState, s.wifi.reason), ('fail', 202));
    expect(s.time, '23:41');
  });

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
