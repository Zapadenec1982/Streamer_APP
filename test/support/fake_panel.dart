import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A panel on the loopback, as far as the app uses one (the firmware's NETWORK.md): the WebSocket
/// gives the whole state and then the keys that changed; a POST takes JSON only (415) — but the
/// firmware image, raw — the login when one is set (401) and a body with its Content-Length (400);
/// a busy panel closes a new socket with 1013.
class FakePanel {
  FakePanel([Map<String, Object?> state = const {}]) : state = {...state};

  final Map<String, Object?> state;

  /// When set, a POST needs Basic [user]:[password] — the streamer's login on. Off, the password
  /// it would have is [keptPassword].
  String? password;
  String user = 'admin';
  String keptPassword = 'modesp';

  /// A new socket is closed with 1013, as when the panel has its three clients.
  bool busy = false;

  Uint8List? cover;

  /// The EQ document (`/api/eq`): its revision, the sound it plays, the sounds it offers and the
  /// bands, as the panel writes them (eq_web.cpp).
  int eqRev = 7;
  String eqPreset = 'rock';
  List<String> eqPresets = const ['custom', 'flat', 'pop', 'rock'];
  List<Object?> eqBands = const [
    {'type': 'lowshelf', 'f': 40, 'gain': 4.9, 'q': 0.707, 'on': true},
    {'type': 'peak', 'f': 62.5, 'gain': 3.6, 'q': 1, 'on': true},
    {'type': 'peak', 'f': 125, 'gain': 0.0, 'q': 1, 'on': false},
  ];

  /// Wi-Fi, the clock and the Bluetooth module as their routes answer.
  Map<String, Object?> wifiScan = const {
    'ok': true,
    'networks': [
      {'ssid': 'Lantern Home', 'rssi': -48, 'auth': 'WPA2'},
      {'ssid': 'Northbound Guest', 'rssi': -71, 'auth': 'open'},
    ],
  };
  Map<String, Object?> wifiAp = const {
    'ssid': 'ModESP-2C4C',
    'channel': 1,
    'password_set': false,
  };
  Map<String, Object?> time = const {
    'time': '23:41',
    'date': '02.11.2026',
    'ntp_enabled': true,
    'timezone': 'EET-2EEST,M3.5.0/3,M10.5.0/4',
    'synced': true,
    'unix': 1793662860,
  };
  Map<String, Object?> bt = const {
    'linked': true,
    'settings': true,
    'known': true,
    'radio': true,
    'name': 'MODEsp',
    'bonds': [],
    'total': 0,
  };

  /// The next POST to /api/wifi or /api/bt is refused with this (status, body), once.
  (int, Map<String, Object?>)? refuseNext;
  int restarts = 0;

  /// The next EQ edit finds the document moved on the panel: 409, once.
  bool eqConflict = false;
  int eqKeeps = 0;

  /// `/api/stations`: its generation, the list and the six presets.
  Map<String, Object?> stations = const {
    'rev': 3,
    'list': {
      'stations': [
        {'name': 'Radio Lantern', 'url': 'http://a.invalid/1', 'uuid': 'u1'},
        {'name': 'Northbound FM', 'url': 'http://a.invalid/2'},
      ],
      'presets': [1, 0, 9, -1, -1, -1],
    },
  };

  /// What runs (`GET /api/ota`), and the image a `POST /api/ota` took.
  Map<String, Object?> ota = const {
    'partition': 'ota_0',
    'version': '0.1.0',
    'idf': 'v5.5.5',
    'date': 'Nov  2 2026',
    'time': '23:58:01',
    'board': 'modesp_p4_player',
  };
  Uint8List? otaImage;

  /// The person's files (`/api/userdata`) and the settings (`/api/backup`) as the panel gives
  /// them; what a restore brought. [badFile] refuses the next files restore over that file.
  Map<String, Object?> userdata = const {
    'modesp_userdata': 1,
    'files': {
      'stations.json': '{"stations":[]}',
      'last_track': '/sdcard/a.flac',
    },
  };
  Map<String, Object?> backup = const {
    'modesp_backup': 1,
    'keys': {'audio.volume': 30, 'ui.backlight': 80},
  };
  Map<String, Object?>? restoredFiles;
  Map<String, Object?>? restoredSettings;
  String? badFile;

  /// The card's index (`/api/library`): paths under [libraryRoot].
  List<String> library = const [];
  int libraryGen = 1;
  String libraryRoot = '/sdcard';

  /// The DLNA browser's snapshot (`/api/dlna/browser`), as the panel sends it.
  Map<String, Object?> dlna = const {
    'revision': 1,
    'busy': false,
    'servers': true,
    'can_back': false,
    'count': 0,
    'next': false,
    'previous': false,
    'title': '@dlna.servers',
    'status': '@dlna.st_not_searched',
    'rows': [],
  };

  final requests =
      <({String method, String path, String? contentType, Object? body})>[];
  int connections = 0;

  late final HttpServer _server;
  final _sockets = <WebSocket>[];
  int _hb = 0;

  int get port => _server.port;
  int get clients => _sockets.length;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() async {
    await dropAll();
    await _server.close(force: true);
  }

  /// The keys changed on the panel's side; the clients hear them as one delta.
  void change(Map<String, Object?> delta) {
    state.addAll(delta);
    _send(delta);
  }

  void heartbeat() => _send({'_hb': ++_hb});

  /// The panel goes away mid-session (a restart, Wi-Fi gone).
  Future<void> dropAll() async {
    for (final ws in [..._sockets]) {
      await ws.close(WebSocketStatus.goingAway);
    }
    _sockets.clear();
  }

  void _send(Map<String, Object?> message) {
    for (final ws in _sockets) {
      ws.add(jsonEncode(message));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
      connections++;
      if (busy) return _refuseBusy(req);
      final ws = await WebSocketTransformer.upgrade(req);
      _sockets.add(ws);
      ws.add(jsonEncode(state));
      ws.listen((_) {}, onDone: () => _sockets.remove(ws));
      return;
    }
    if (req.method == 'POST' && path == '/api/ota') return _ota(req);
    final text = await utf8.decodeStream(req);
    Object? body;
    try {
      body = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      body = text;
    }
    requests.add((
      method: req.method,
      path: path,
      contentType: req.headers.contentType?.mimeType,
      body: body,
    ));
    if (req.method == 'POST' &&
        req.headers.contentType?.mimeType != 'application/json') {
      return _reply(req, 415, {'error': 'content_type'});
    }
    if (req.method == 'POST' && !_authorized(req)) {
      return _reply(req, 401, {'error': 'unauthorized'});
    }
    // httpd reads a body by its Content-Length alone: one sent in chunks arrives empty
    // (http_routes::read_small_body)
    if (req.method == 'POST' && req.contentLength <= 0) {
      req.response
        ..statusCode = 400
        ..write('Empty body');
      return req.response.close();
    }
    switch ((req.method, path)) {
      case ('GET', '/api/ota'):
        return _reply(req, 200, ota);
      case ('GET', '/api/auth'):
        return _reply(req, 200, {
          'enabled': password != null,
          'username': user,
        });
      // new_pass needs current_pass; all checked before anything is written
      case ('POST', '/api/auth'):
        final b = (body! as Map).cast<String, Object?>();
        final now = password ?? keptPassword;
        if (b['new_pass'] is String && b['current_pass'] != now) {
          return _reply(req, 403, {'error': 'wrong_password'});
        }
        if (b['username'] case final String name) user = name;
        final next = b['new_pass'] is String ? b['new_pass']! as String : now;
        final on = b['enabled'] is bool
            ? b['enabled']! as bool
            : password != null;
        password = on ? next : null;
        keptPassword = next;
        return _reply(req, 200, {'ok': true});
      case ('GET', '/api/userdata'):
        return _reply(req, 200, userdata);
      case ('POST', '/api/userdata'):
        if (badFile case final file?) {
          badFile = null;
          return _reply(req, 400, {'error': 'bad_file', 'file': file});
        }
        restoredFiles = (body! as Map).cast<String, Object?>();
        final files = restoredFiles!['files'];
        return _reply(req, 200, {
          'ok': true,
          'staged': files is Map ? files.length : 0,
        });
      case ('GET', '/api/backup'):
        return _reply(req, 200, backup);
      case ('POST', '/api/restore'):
        restoredSettings = (body! as Map).cast<String, Object?>();
        return _reply(req, 200, {'ok': true});
      case ('POST', '/api/settings'):
        _apply((body! as Map).cast<String, Object?>());
        return _reply(req, 200, {'ok': true});
      // the whole state, as the poll of a page that shows diagnostics reads it
      case ('GET', '/api/state'):
        return _reply(req, 200, state);
      case ('GET', '/api/wifi/scan'):
        return _reply(req, 200, wifiScan);
      case ('GET', '/api/wifi/ap'):
        return _reply(req, 200, wifiAp);
      case ('POST', '/api/wifi/ap'):
        return _reply(req, 200, {'ok': true});
      case ('GET', '/api/time'):
        return _reply(req, 200, time);
      case ('POST', '/api/time'):
        return _reply(req, 200, {'ok': true});
      case ('GET', '/api/bt'):
        return _reply(req, 200, bt);
      case ('POST', '/api/wifi') || ('POST', '/api/bt'):
        if (refuseNext case (final status, final reply)) {
          refuseNext = null;
          return _reply(req, status, reply);
        }
        return _reply(req, 200, {'ok': true});
      case ('POST', '/api/restart'):
        restarts++;
        return _reply(req, 200, {'ok': true});
      case ('GET', '/api/eq'):
        return _reply(req, 200, {
          'rev': eqRev,
          'fs': 48000,
          'preset': eqPreset,
          'presets': eqPresets,
          'bands': eqBands,
        });
      case ('POST', '/api/eq'):
        final edit = (body! as Map).cast<String, Object?>();
        if (edit['keep'] == true) {
          eqKeeps++;
          return _reply(req, 200, {'rev': eqRev});
        }
        if (eqConflict) {
          eqConflict = false;
          eqRev++;
          return _reply(req, 409, {'error': 'changed', 'rev': eqRev});
        }
        if (edit['rev'] != eqRev) {
          return _reply(req, 409, {'error': 'changed', 'rev': eqRev});
        }
        // a set by hand is «Власний» (eq_hand_edited); "keep" with it writes it at once
        if (edit['bands'] case final List bands) {
          eqBands = bands;
          eqPreset = 'custom';
          if (edit['keep'] == true) eqKeeps++;
        } else {
          eqPreset = edit['preset']! as String;
        }
        eqRev++;
        change({'audio.eq_rev': eqRev});
        return _reply(req, 200, {'rev': eqRev});
      case ('GET', '/api/stations'):
        return _reply(req, 200, stations);
      // the whole list back with the generation it was made from: queued (202), or refused when
      // the list moved meanwhile (409)
      case ('POST', '/api/stations'):
        final edit = (body! as Map).cast<String, Object?>();
        final rev = stations['rev'];
        if (edit['rev'] != rev) {
          return _reply(req, 409, {'error': 'changed'});
        }
        stations = {
          'rev': (rev! as int) + 1,
          'list': {'stations': edit['stations'], 'presets': edit['presets']},
        };
        change({'radio.list_rev': stations['rev']});
        return _reply(req, 202, {'ok': true});
      case ('GET', '/radio_genres.json'):
        return _reply(req, 200, {
          'genres': [
            {
              'name': 'Джаз',
              'name_en': 'Jazz',
              'name_de': 'Jazz',
              'tag': 'jazz',
            },
            {'name': 'Без тегу'},
          ],
        });
      case ('GET', '/api/library'):
        final from = int.tryParse(req.uri.queryParameters['from'] ?? '') ?? 0;
        final n = int.tryParse(req.uri.queryParameters['n'] ?? '') ?? 100;
        final start = from.clamp(0, library.length);
        return _reply(req, 200, {
          'gen': libraryGen,
          'busy': false,
          'count': library.length,
          'cursor': -1,
          'root': libraryRoot,
          'from': start,
          'rows': library.sublist(start, (start + n).clamp(0, library.length)),
        });
      case ('GET', '/api/dlna/browser'):
        return _reply(req, 200, dlna);
      case ('GET', '/api/cover'):
        final bytes = cover;
        if (bytes == null) return _reply(req, 404, {'error': 'not_found'});
        final etag = '"${bytes.length}"';
        if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
          req.response.statusCode = 304;
        } else {
          req.response.headers.set(HttpHeaders.etagHeader, etag);
          req.response.add(bytes);
        }
        await req.response.close();
        return;
      default:
        return _reply(req, 404, {'error': 'not_found'});
    }
  }

  bool _authorized(HttpRequest req) =>
      password == null ||
      req.headers.value(HttpHeaders.authorizationHeader) ==
          'Basic ${base64.encode(utf8.encode('$user:$password'))}';

  /// `POST /api/ota` as the panel takes it (http_service.cpp): the raw image with its
  /// Content-Length and the login; 256 B … 4 MB; 0xE9 first; the board's project_name.
  Future<void> _ota(HttpRequest req) async {
    final bytes = await req.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (b, d) => b..add(d),
    );
    final image = bytes.takeBytes();
    requests.add((
      method: req.method,
      path: '/api/ota',
      contentType: req.headers.contentType?.mimeType,
      body: image.length,
    ));
    Future<void> plain(int status, String text) {
      req.response
        ..statusCode = status
        ..write(text);
      return req.response.close();
    }

    if (!_authorized(req)) return _reply(req, 401, {'error': 'unauthorized'});
    if (req.contentLength <= 0) return plain(400, 'Empty body');
    if (image.length > 4 * 1024 * 1024) return plain(400, 'Firmware too large');
    if (image.length < 256) return plain(400, 'File too small');
    if (image[0] != 0xE9) return plain(400, 'Not a valid ESP32 firmware');
    final desc = ByteData.sublistView(image).getUint32(0x20, Endian.little);
    if (desc == 0xABCD5432) {
      final field = image.sublist(0x50, 0x70);
      final end = field.indexOf(0);
      final incoming = utf8.decode(end < 0 ? field : field.sublist(0, end));
      final running = ota['board']! as String;
      if (incoming != running) {
        return _reply(req, 400, {
          'error': 'board_mismatch',
          'running': running,
          'incoming': incoming,
        });
      }
    }
    otaImage = image;
    restarts++;
    return _reply(req, 200, {
      'status': 'ok',
      'message': 'Firmware updated. Restarting...',
    });
  }

  void _apply(Map<String, Object?> body) {
    final delta = <String, Object?>{};
    for (final MapEntry(:key, :value) in body.entries) {
      if (key == 'audio.transport') {
        if (value == 6) {
          delta['bt.play_state'] = state['bt.play_state'] == 'playing'
              ? 'paused'
              : 'playing';
        }
        continue;
      }
      if (key == 'radio.cmd') continue;
      delta[key] = value;
    }
    change(delta);
  }

  /// The handshake, then a close frame with 1013 at once, as the panel's httpd sends a client it
  /// has no slot for. dart:io will not send 1013 itself (it counts the code as reserved), so the
  /// frame is written by hand.
  Future<void> _refuseBusy(HttpRequest req) async {
    final key = req.headers.value('sec-websocket-key')!;
    final accept = base64.encode(
      sha1
          .convert(utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))
          .bytes,
    );
    req.response
      ..statusCode = HttpStatus.switchingProtocols
      ..headers.set(HttpHeaders.connectionHeader, 'Upgrade')
      ..headers.set(HttpHeaders.upgradeHeader, 'websocket')
      ..headers.set('Sec-WebSocket-Accept', accept);
    final socket = await req.response.detachSocket();
    socket.add(const [0x88, 0x02, 0x03, 0xF5]); // FIN + close, 2 bytes: 1013
    await socket.flush();
    await socket.close();
  }

  Future<void> _reply(HttpRequest req, int status, Object body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }
}

/// Waits for [condition], failing after [limit].
Future<void> until(
  bool Function() condition, {
  Duration limit = const Duration(seconds: 3),
}) async {
  final end = DateTime.now().add(limit);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('condition not met within $limit');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
