import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/streamer.dart';

/// The streamer's settings as the web's pages read them: the networks nearby, their signal and
/// what may be joined; why a join failed; the limits of a password and a name; the Bluetooth
/// module's answer and its pairing code.
void main() {
  test('the networks nearby: one row per name, its strongest, strongest first; '
      'none when the streamer could not look', () {
    final nets = networksOf({
      'ok': true,
      'networks': [
        {'ssid': 'Home', 'rssi': -70, 'auth': 'WPA2'},
        {'ssid': 'Home', 'rssi': -50, 'auth': 'WPA2'},
        {'ssid': '', 'rssi': -40, 'auth': 'open'},
        {'ssid': 'Cafe', 'rssi': -60, 'auth': 'open'},
        {'ssid': 'Attic', 'rssi': -85, 'auth': 'WEP'},
      ],
    })!;
    expect(
      [for (final n in nets) (n.ssid, n.rssi)],
      [('Home', -50), ('Cafe', -60), ('Attic', -85)],
    );
    expect(networksOf({'ok': false}), isNull);
  });

  test('what may be joined, and the glass\'s four bars', () {
    WifiNetwork n(String auth, [int rssi = -60]) =>
        WifiNetwork(ssid: 'x', rssi: rssi, auth: auth);
    for (final a in ['open', 'WPA2', 'WPA/WPA2', 'WPA3', 'WPA2/WPA3']) {
      expect(n(a).canJoin, isTrue, reason: a);
    }
    for (final a in ['WEP', 'WPA', 'WPA2-Enterprise', 'unknown', '']) {
      expect(n(a).canJoin, isFalse, reason: a);
    }
    expect([-55, -56, -67, -68, -75, -76].map((r) => n('open', r).bars), [
      4,
      3,
      3,
      2,
      2,
      1,
    ]);
  });

  test('why a join failed, as the glass says it', () {
    for (final c in [2, 15, 202, 204, 14]) {
      expect(WifiWhy.of(c), WifiWhy.password, reason: '$c');
    }
    expect(WifiWhy.of(201), WifiWhy.notFound);
    expect(WifiWhy.of(210), WifiWhy.security);
    expect(WifiWhy.of(211), WifiWhy.security);
    expect(WifiWhy.of(0), WifiWhy.silent);
    expect(WifiWhy.of(8), WifiWhy.refused);
  });

  test('a password and a name are held to what the streamer takes', () {
    expect(joinPasswordOk('1234567'), isFalse);
    expect(joinPasswordOk('12345678'), isTrue);
    expect(joinPasswordOk('ж' * 32), isTrue, reason: '64 bytes');
    expect(joinPasswordOk('ж' * 33), isFalse, reason: '66 bytes');
    expect(apPasswordOk('a' * 63), isTrue);
    expect(apPasswordOk('a' * 64), isFalse);
    // the firmware's JSON reader keeps a backslash: such a string is not sent
    expect(sendable('pass"word'), isFalse);
    expect(sendable(r'pass\word'), isFalse);
    expect(sendable('пароль 1'), isTrue);
  });

  test(
    'the Bluetooth module\'s answer, and its code as the glass shows it',
    () {
      final bt = BtInfo.fromJson({
        'linked': true,
        'settings': true,
        'known': true,
        'radio': true,
        'discoverable': false,
        'auto_reconnect': true,
        'name': 'MODEsp',
        'codecs_supported': 31,
        'codecs_enabled': 3,
        'total': 2,
        'bonds': [
          {'addr': 'AA:BB:CC:DD:EE:FF', 'name': 'Phone', 'connected': true},
          {'addr': '11:22:33:44:55:66', 'last': true},
          {'name': 'no address'},
        ],
        'pairing': {'seq': 4, 'active': true, 'code': 7012},
      });
      expect((bt.linked, bt.settings, bt.known), (true, true, true));
      expect(
        (bt.radio, bt.discoverable, bt.autoReconnect),
        (true, false, true),
      );
      expect((bt.codecsSupported, bt.codecsEnabled), (31, 3));
      expect(
        [for (final b in bt.bonds) b.addr],
        ['AA:BB:CC:DD:EE:FF', '11:22:33:44:55:66'],
      );
      expect((bt.pairingSeq, bt.pairingCode), (4, 7012));
      expect(pairCode(7012), '007 012');
      expect(pairCode(482916), '482 916');
      expect(btRefusal('answered'), BtRefusal.answered);
      expect(btRefusal('name'), BtRefusal.name);
      expect(btRefusal('teapot'), BtRefusal.other);
    },
  );

  test('the clock and the access point as the streamer says them', () {
    final t = PanelTime.fromJson({
      'time': '23:41',
      'date': '02.11.2026',
      'ntp_enabled': false,
      'timezone': 'EET-2EEST,M3.5.0/3,M10.5.0/4',
      'synced': true,
      'unix': 1793662860,
    });
    expect((t.ntp, t.synced, t.unix), (false, true, 1793662860));
    expect(timezones.any((z) => z.tz == t.timezone), isTrue);
    final ap = WifiAp.fromJson({
      'ssid': 'ModESP-2C4C',
      'channel': 6,
      'password_set': true,
    });
    expect((ap.ssid, ap.channel, ap.passwordSet), ('ModESP-2C4C', 6, true));
  });
}
