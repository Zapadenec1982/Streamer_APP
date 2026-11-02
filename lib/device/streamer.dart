/// The streamer's own settings, as the web's Налаштування pages have them: the screen, the
/// language, the services, Bluetooth and its pairing, Wi-Fi and the clock — what the WebSocket
/// says of them, and the answers of `/api/bt`, `/api/wifi` and `/api/time` (the firmware's
/// NETWORK.md, "REST API"; AUDIO.md, "Control from the panel and the phone").
library;

import 'dart:convert';

import 'keys.dart';

/// A setting a control moves on the screen's page and the language's: its key, and the range the
/// streamer holds it to (test/keys_test.dart holds them to protocol/state_meta.json).
enum PanelSetting {
  backlight(Keys.uiBacklight, 0, 100, 5),
  standbyBacklight(Keys.uiStandbyBl, 5, 100, 5),
  sleepMinutes(Keys.uiStandbyMin, 0, 60, 5),
  scheme(Keys.uiTheme, 0, 3, 1),

  /// ui.lang: 0 Українська, 1 English, 2 Deutsch, 3 Polski (the web's lib/lang.js LANGS).
  language(Keys.uiLang, 0, 3, 1);

  const PanelSetting(this.key, this.min, this.max, this.step);

  final StateKey<int> key;
  final int min;
  final int max;
  final int step;
}

/// The services' switches.
enum PanelSwitch {
  airplay(Keys.airplayEnabled),
  dlna(Keys.dlnaEnabled),
  covers(Keys.radioCovers);

  const PanelSwitch(this.key);

  final StateKey<bool> key;
}

/// The glass's auto-sleep steps (screen_display.cpp SLEEP_STEPS): minutes, 0 never.
const sleepSteps = [0, 5, 10, 15, 20, 30, 45, 60];

/// The streamer's languages, in ui.lang's order, by their own names.
const panelLanguages = ['Українська', 'English', 'Deutsch', 'Polski'];

/// The schemes' swatches, ui.theme's order: each one's primary (the web's lib/schemes.js).
const schemeSwatches = [0xFFFFB95F, 0xFF7A82C0, 0xFF9A9973, 0xFFC45D4A];

/// A phone asking to pair (bt.pair_*): on the glass and in every client at once; the first
/// answer wins.
class PairingState {
  const PairingState({
    this.seq = 0,
    this.active = false,
    this.kind = PairKind.numeric,
    this.name = '',
    this.by = 0,
    this.result = 255,
  });

  /// Which request it is: a new number is a new question.
  final int seq;
  final bool active;
  final PairKind kind;

  /// The phone's name, '' when it gave none.
  final String name;

  /// Who answered: 1 the glass, 2 a client (the web or an app), 0 nobody yet.
  final int by;

  /// 0 paired, 1 refused, 2 no answer in time, another a failure; 255 still waiting.
  final int result;
}

/// How a pairing is confirmed (sat::PAIR_*).
enum PairKind {
  /// The same six digits on both: compare them.
  numeric,

  /// No code: yes or no.
  consent,

  /// The phone asks for the code: type it there.
  passkey;

  static PairKind of(int? v) => switch (v) {
    1 => consent,
    2 => passkey,
    _ => numeric,
  };
}

/// Wi-Fi as the WebSocket says it.
class WifiState {
  const WifiState({
    this.mode = '',
    this.connected = false,
    this.ssid = '',
    this.ip = '',
    this.tryState = '',
    this.trySsid = '',
    this.reason = 0,
  });

  /// "sta" on a network, "ap" its own access point.
  final String mode;

  /// It has an address in STA.
  final bool connected;

  /// The network, or the access point's name.
  final String ssid;
  final String ip;

  /// A join: "connecting", "ok", "fail"; '' none.
  final String tryState;
  final String trySsid;

  /// Why the last connection went (wifi_err_reason_t).
  final int reason;

  bool get trying => tryState == 'connecting';

  /// The network it is on, or null.
  String? get network => connected && mode == 'sta' ? ssid : null;
}

/// The streamer's own settings in a snapshot.
class StreamerState {
  const StreamerState({
    this.backlight = 80,
    this.standbyBacklight = 25,
    this.sleepMinutes = 5,
    this.language,
    this.airplay,
    this.airplayMode = 0,
    this.airplayModeError = '',
    this.airplaySwitching = false,
    this.airplayModeStatus = '',
    this.dlna,
    this.covers,
    this.btLink = false,
    this.btPeer = '',
    this.btCodec = '',
    this.btConfigRev = 0,
    this.pairing = const PairingState(),
    this.wifi = const WifiState(),
    this.time = '',
    this.date = '',
  });

  final int backlight;
  final int standbyBacklight;
  final int sleepMinutes;

  /// ui.lang, null where the streamer has not said.
  final int? language;

  /// The services' switches, null where the streamer has none.
  final bool? airplay;

  /// 0 AirPlay 2, 1 AirPlay 1 for Windows.
  final int airplayMode;

  /// What is happening to the mode — catalog messages, '' for nothing.
  final String airplayModeError;
  final bool airplaySwitching;
  final String airplayModeStatus;
  final bool? dlna;
  final bool? covers;

  /// The Bluetooth module answers; the phone connected to it, its codec.
  final bool btLink;
  final String btPeer;
  final String btCodec;

  /// Moves when the Bluetooth settings do: a page that shows them reads them again.
  final int btConfigRev;
  final PairingState pairing;
  final WifiState wifi;

  /// The clock: "HH:MM" and the date, as the streamer says them ("--:--" until it is set).
  final String time;
  final String date;
}

/// The access point's address (wifi_service.cpp start_ap(): always).
const accessPointIp = '192.168.4.1';

/// A network the streamer hears (`GET /api/wifi/scan`).
class WifiNetwork {
  const WifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.auth,
  });

  final String ssid;

  /// dBm.
  final int rssi;

  /// "open", "WPA2", "WPA/WPA2", "WPA3", "WPA2/WPA3", "WEP", "WPA", …
  final String auth;

  /// What the streamer joins (screen_wifi.cpp supported()); everything else the scan names is
  /// shown and refused.
  static const joinable = {'open', 'WPA2', 'WPA/WPA2', 'WPA3', 'WPA2/WPA3'};

  /// Old security the streamer does not join.
  static const old = {'WEP', 'WPA'};

  bool get canJoin => joinable.contains(auth);

  bool get open => auth == 'open';

  /// The glass's signal steps (signal_icon()): 1…4 bars.
  int get bars => rssi >= -55
      ? 4
      : rssi >= -67
      ? 3
      : rssi >= -75
      ? 2
      : 1;
}

/// The networks nearby: one row per name, its strongest, strongest first; null when the streamer
/// could not look (`{"ok":false}`: busy joining, or short of memory).
List<WifiNetwork>? networksOf(Object? json) {
  final d = json is Map ? json : const {};
  if (d['ok'] != true) return null;
  final best = <String, WifiNetwork>{};
  for (final n in d['networks'] is List ? d['networks'] as List : const []) {
    if (n is! Map || n['ssid'] is! String || (n['ssid'] as String).isEmpty) {
      continue;
    }
    final net = WifiNetwork(
      ssid: n['ssid'] as String,
      rssi: n['rssi'] is int ? n['rssi'] as int : -100,
      auth: n['auth'] is String ? n['auth'] as String : '',
    );
    final seen = best[net.ssid];
    if (seen == null || net.rssi > seen.rssi) best[net.ssid] = net;
  }
  return best.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
}

/// Why a join failed, as the glass says it (screen_wifi.cpp reason_text(); the codes are
/// esp_wifi_types_generic.h's, IDF v5.5.5).
enum WifiWhy {
  password,
  notFound,
  security,
  silent,
  refused;

  static WifiWhy of(int code) => switch (code) {
    // AUTH_EXPIRE, 4WAY_HANDSHAKE_TIMEOUT, AUTH_FAIL, HANDSHAKE_TIMEOUT, MIC_FAILURE
    2 || 15 || 202 || 204 || 14 => password,
    // NO_AP_FOUND
    201 => notFound,
    // NO_AP_FOUND_W_COMPATIBLE_SECURITY, NO_AP_FOUND_IN_AUTHMODE_THRESHOLD
    210 || 211 => security,
    0 => silent,
    _ => refused,
  };
}

/// UTF-8 bytes, which the streamer's limits count.
int utf8Length(String s) => utf8.encode(s).length;

/// A password the streamer takes for a network: 8…64 bytes; and for its own access point: 8…63.
bool joinPasswordOk(String p) => p.length >= 8 && utf8Length(p) <= 64;

bool apPasswordOk(String p) => p.length >= 8 && utf8Length(p) <= 63;

/// The firmware's JSON reader does not unescape strings: a `"` or a `\` would reach the streamer
/// with its backslash. Such a name or password is not sent (the web's WifiPage).
bool sendable(String s) => !s.contains('"') && !s.contains(r'\');

/// The access point (`GET /api/wifi/ap`): its name, channel and whether it has a password.
class WifiAp {
  const WifiAp({
    required this.ssid,
    required this.channel,
    required this.passwordSet,
  });

  final String ssid;
  final int channel;
  final bool passwordSet;

  static WifiAp fromJson(Object? json) {
    final d = json is Map ? json : const {};
    return WifiAp(
      ssid: d['ssid'] is String ? d['ssid'] as String : '',
      channel: d['channel'] is int ? d['channel'] as int : 1,
      passwordSet: d['password_set'] == true,
    );
  }
}

/// The clock (`GET /api/time`).
class PanelTime {
  const PanelTime({
    required this.time,
    required this.date,
    required this.ntp,
    required this.timezone,
    required this.synced,
    required this.unix,
  });

  final String time;
  final String date;

  /// From the internet (NTP), or set by hand.
  final bool ntp;

  /// A POSIX TZ string.
  final String timezone;

  /// The clock has been set.
  final bool synced;

  /// Seconds since 1970.
  final int unix;

  static PanelTime fromJson(Object? json) {
    final d = json is Map ? json : const {};
    return PanelTime(
      time: d['time'] is String ? d['time'] as String : '',
      date: d['date'] is String ? d['date'] as String : '',
      ntp: d['ntp_enabled'] != false,
      timezone: d['timezone'] is String ? d['timezone'] as String : '',
      synced: d['synced'] == true,
      unix: d['unix'] is int ? d['unix'] as int : 0,
    );
  }
}

/// The time zones offered, as POSIX TZ strings — what POST /api/time stores and setenv("TZ")
/// takes (the web's lib/timezones.js).
const timezones = [
  (label: 'UTC-12', tz: 'UTC12'),
  (label: 'UTC-11', tz: 'UTC11'),
  (label: 'UTC-10 (Hawaii)', tz: 'HST10'),
  (label: 'UTC-9 (Alaska)', tz: 'AKST9AKDT,M3.2.0,M11.1.0'),
  (label: 'UTC-8 (Los Angeles)', tz: 'PST8PDT,M3.2.0,M11.1.0'),
  (label: 'UTC-7 (Denver)', tz: 'MST7MDT,M3.2.0,M11.1.0'),
  (label: 'UTC-6 (Chicago)', tz: 'CST6CDT,M3.2.0,M11.1.0'),
  (label: 'UTC-5 (New York)', tz: 'EST5EDT,M3.2.0,M11.1.0'),
  (label: 'UTC-4', tz: 'AST4'),
  (label: 'UTC-3 (Sao Paulo)', tz: 'BRT3'),
  (label: 'UTC-2', tz: 'BRST2'),
  (label: 'UTC-1', tz: 'CVT1'),
  (label: 'UTC+0 (London)', tz: 'GMT0BST,M3.5.0/1,M10.5.0'),
  (label: 'UTC+1 (Berlin)', tz: 'CET-1CEST,M3.5.0,M10.5.0/3'),
  (label: 'UTC+2 (Kyiv)', tz: 'EET-2EEST,M3.5.0/3,M10.5.0/4'),
  (label: 'UTC+3 (Moscow)', tz: 'MSK-3'),
  (label: 'UTC+4 (Dubai)', tz: 'GST-4'),
  (label: 'UTC+5 (Tashkent)', tz: 'PKT-5'),
  (label: 'UTC+5:30 (India)', tz: 'IST-5:30'),
  (label: 'UTC+6 (Almaty)', tz: 'ALMT-6'),
  (label: 'UTC+7 (Bangkok)', tz: 'ICT-7'),
  (label: 'UTC+8 (Singapore)', tz: 'SGT-8'),
  (label: 'UTC+9 (Tokyo)', tz: 'JST-9'),
  (label: 'UTC+10 (Sydney)', tz: 'AEST-10AEDT,M10.1.0,M4.1.0/3'),
  (label: 'UTC+12 (Auckland)', tz: 'NZST-12NZDT,M9.5.0,M4.1.0/3'),
];

/// A phone the Bluetooth module remembers.
class BtBond {
  const BtBond({
    required this.addr,
    this.name = '',
    this.connected = false,
    this.last = false,
  });

  /// "AA:BB:CC:DD:EE:FF".
  final String addr;
  final String name;
  final bool connected;

  /// The one connected last.
  final bool last;
}

/// The optional codecs, as the glass's chips show them (screen_bt.cpp); SBC is bit 0, always on.
const btCodecs = [
  (bit: 1 << 1, name: 'AAC'),
  (bit: 1 << 2, name: 'aptX'),
  (bit: 1 << 3, name: 'aptX HD'),
  (bit: 1 << 4, name: 'LHDC'),
];

/// The device name: 1…32 bytes of UTF-8 (sat::BT_NAME_MAX).
const btNameMax = 32;

/// The Bluetooth module's settings (`GET /api/bt`).
class BtInfo {
  const BtInfo({
    this.linked = false,
    this.settings = false,
    this.known = false,
    this.radio = false,
    this.discoverable = false,
    this.autoReconnect = false,
    this.name = '',
    this.codecsSupported = 1,
    this.codecsEnabled = 1,
    this.bonds = const [],
    this.total = 0,
    this.pairingSeq = 0,
    this.pairingCode,
  });

  /// The module answers.
  final bool linked;

  /// It speaks protocol 1.8: its settings can be read and changed; an older one only disconnects.
  final bool settings;

  /// It has sent them: until then the switches wait.
  final bool known;
  final bool radio;
  final bool discoverable;
  final bool autoReconnect;
  final String name;
  final int codecsSupported;
  final int codecsEnabled;
  final List<BtBond> bonds;
  final int total;

  /// The pairing request the code is for, and its six digits; null while none waits.
  final int pairingSeq;
  final int? pairingCode;

  BtInfo copyWith({
    bool? radio,
    bool? discoverable,
    bool? autoReconnect,
    int? codecsEnabled,
  }) => BtInfo(
    linked: linked,
    settings: settings,
    known: known,
    radio: radio ?? this.radio,
    discoverable: discoverable ?? this.discoverable,
    autoReconnect: autoReconnect ?? this.autoReconnect,
    name: name,
    codecsSupported: codecsSupported,
    codecsEnabled: codecsEnabled ?? this.codecsEnabled,
    bonds: bonds,
    total: total,
    pairingSeq: pairingSeq,
    pairingCode: pairingCode,
  );

  static BtInfo fromJson(Object? json) {
    final d = json is Map ? json : const {};
    final p = d['pairing'] is Map ? d['pairing'] as Map : const {};
    int number(Map m, String k, int or) => m[k] is int ? m[k] as int : or;
    return BtInfo(
      linked: d['linked'] == true,
      settings: d['settings'] == true,
      known: d['known'] == true,
      radio: d['radio'] == true,
      discoverable: d['discoverable'] == true,
      autoReconnect: d['auto_reconnect'] == true,
      name: d['name'] is String ? d['name'] as String : '',
      codecsSupported: number(d, 'codecs_supported', 1),
      codecsEnabled: number(d, 'codecs_enabled', 1),
      bonds: [
        for (final b in d['bonds'] is List ? d['bonds'] as List : const [])
          if (b is Map && b['addr'] is String)
            BtBond(
              addr: b['addr'] as String,
              name: b['name'] is String ? b['name'] as String : '',
              connected: b['connected'] == true,
              last: b['last'] == true,
            ),
      ],
      total: number(d, 'total', 0),
      pairingSeq: number(p, 'seq', 0),
      pairingCode: p['code'] is int ? p['code'] as int : null,
    );
  }
}

/// The six digits as the glass shows them: "123 456".
String pairCode(int n) {
  final s = '$n'.padLeft(6, '0');
  return '${s.substring(0, 3)} ${s.substring(3)}';
}

/// Why the Bluetooth module turned a request down (409 `{"error":…}`).
enum BtRefusal { noSatellite, oldSatellite, notKnownYet, name, answered, other }

BtRefusal btRefusal(String? code) => switch (code) {
  'no_satellite' => BtRefusal.noSatellite,
  'old_satellite' => BtRefusal.oldSatellite,
  'not_known_yet' => BtRefusal.notKnownYet,
  'name' => BtRefusal.name,
  'answered' => BtRefusal.answered,
  _ => BtRefusal.other,
};
