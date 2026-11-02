import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A panel on the loopback, as far as the app uses one (the firmware's NETWORK.md): the WebSocket
/// gives the whole state and then the keys that changed; POST /api/settings takes JSON only (415)
/// and the login when one is set (401); a busy panel closes a new socket with 1013.
class FakePanel {
  FakePanel([Map<String, Object?> state = const {}]) : state = {...state};

  final Map<String, Object?> state;

  /// When set, a POST needs Basic admin:[password].
  String? password;

  /// A new socket is closed with 1013, as when the panel has its three clients.
  bool busy = false;

  Uint8List? cover;

  /// The EQ document (`/api/eq`): its revision, the sound it plays, the sounds it offers.
  int eqRev = 7;
  String eqPreset = 'rock';
  List<String> eqPresets = const ['custom', 'flat', 'pop', 'rock'];

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
    if (req.method == 'POST' &&
        password != null &&
        req.headers.value(HttpHeaders.authorizationHeader) !=
            'Basic ${base64.encode(utf8.encode('admin:$password'))}') {
      return _reply(req, 401, {'error': 'unauthorized'});
    }
    switch ((req.method, path)) {
      case ('GET', '/api/ota'):
        return _reply(req, 200, {
          'board': 'modesp_p4_player',
          'version': '0.1.0',
        });
      case ('POST', '/api/settings'):
        _apply((body! as Map).cast<String, Object?>());
        return _reply(req, 200, {'ok': true});
      case ('GET', '/api/eq'):
        return _reply(req, 200, {
          'rev': eqRev,
          'fs': 48000,
          'preset': eqPreset,
          'presets': eqPresets,
          'bands': const [],
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
        eqPreset = edit['preset']! as String;
        eqRev++;
        change({'audio.eq_rev': eqRev});
        return _reply(req, 200, {'rev': eqRev});
      case ('GET', '/api/stations'):
        return _reply(req, 200, stations);
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
