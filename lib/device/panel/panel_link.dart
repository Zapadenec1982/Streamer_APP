import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models.dart';
import 'endpoint.dart';

/// A refusal from the panel's HTTP API.
class PanelError implements Exception {
  const PanelError(this.status, [this.code]);

  /// The HTTP status; 0 when the panel did not answer at all.
  final int status;

  /// The panel's own word for it (`{"error": code}`), when it gave one.
  final String? code;

  bool get unauthorized => status == 401;

  /// Five wrong logins in a row: every checked request gets 429 for 30 s.
  bool get locked => status == 429;

  @override
  String toString() => 'PanelError($status${code == null ? '' : ', $code'})';
}

/// The panel's state, heard over its WebSocket, and its HTTP API (the firmware's NETWORK.md,
/// "WebSocket /ws" and "REST API").
///
/// The socket brings the whole state first and then the keys that changed. Keys starting with
/// `_` are the panel's service messages — `{"_hb":n}` every 5 s — never state. When the panel
/// closes the socket, or goes silent for [silence] after it has sent a heartbeat, the link
/// connects again: 1, 2, 4 … 30 s apart with some jitter, or every [busyRetry] while the panel
/// says it is busy (close code 1013). [stop] lets go of the socket — the app does that in the
/// background, so as not to hold one of the panel's three slots — and [start] takes one again.
class PanelLink {
  PanelLink(
    this.endpoint, {
    this.backoff = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ],
    this.busyRetry = const Duration(seconds: 5),
    this.silence = const Duration(seconds: 15),
    this.timeout = const Duration(seconds: 6),
    Random? random,
  }) : _random = random ?? Random() {
    _http.connectionTimeout = timeout;
  }

  PanelEndpoint endpoint;
  final List<Duration> backoff;
  final Duration busyRetry;
  final Duration silence;
  final Duration timeout;
  final Random _random;

  final _http = HttpClient();
  final _changes = StreamController<void>.broadcast();
  Map<String, Object?> _state = const {};
  LinkStatus _status = LinkStatus.connecting;
  bool _known = false;
  bool _running = false;
  bool _heartbeat = false;
  int _attempt = 0;
  WebSocket? _socket;
  Timer? _retry;
  Timer? _quiet;

  /// The panel's state as last heard; empty until it has spoken once.
  Map<String, Object?> get state => _state;

  LinkStatus get status => _status;

  /// The panel has sent its state at least once.
  bool get known => _known;

  /// Something in [state] or [status] changed.
  Stream<void> get changes => _changes.stream;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _quiet?.cancel();
    final socket = _socket;
    _socket = null;
    await socket?.close(WebSocketStatus.normalClosure);
  }

  Future<void> dispose() async {
    await stop();
    _http.close(force: true);
    await _changes.close();
  }

  /// Writes keys: `POST /api/settings`. The panel's answer comes back as state, over the socket.
  Future<void> write(Map<String, Object?> values) =>
      postJson('/api/settings', values);

  /// A JSON POST of the HTTP API; the panel's JSON answer. [ok] are the statuses that mean it was
  /// taken — 202 where the panel queues the work.
  Future<Object?> postJson(
    String path,
    Map<String, Object?> body, {
    List<int> ok = const [200],
  }) async {
    final res = await _send('POST', endpoint.http(path), jsonEncode(body));
    final text = await _drain(res, ok: ok);
    return text.isEmpty ? null : jsonDecode(text);
  }

  /// A JSON GET of the HTTP API.
  Future<Object?> getJson(String path, [Map<String, String>? query]) async {
    final res = await _send('GET', endpoint.http(path, query));
    final text = await _drain(res, ok: const [200]);
    return jsonDecode(text);
  }

  /// A file of the HTTP API. [etag] names the copy the app keeps: the panel answers 304 when
  /// that is still the one, 404 when it has none; the bytes come only with a 200.
  Future<({int status, Uint8List bytes, String? etag})> getBytes(
    String path, {
    Map<String, String>? query,
    String? etag,
  }) async {
    final res = await _send('GET', endpoint.http(path, query), null, etag);
    if (res.statusCode == HttpStatus.notModified ||
        res.statusCode == HttpStatus.notFound) {
      await res.drain<void>();
      return (status: res.statusCode, bytes: Uint8List(0), etag: etag);
    }
    if (res.statusCode != HttpStatus.ok) {
      await _drain(res, ok: const [200]);
    }
    final bytes = await res.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (b, d) => b..add(d),
    );
    return (
      status: res.statusCode,
      bytes: bytes.takeBytes(),
      etag: res.headers.value(HttpHeaders.etagHeader),
    );
  }

  Future<HttpClientResponse> _send(
    String method,
    Uri uri, [
    String? json,
    String? etag,
  ]) async {
    try {
      final req = await _http.openUrl(method, uri).timeout(timeout);
      final auth = endpoint.authorization;
      if (auth != null) req.headers.set(HttpHeaders.authorizationHeader, auth);
      if (etag != null) req.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      if (json != null) {
        // The panel takes a POST only as application/json (415 otherwise), and reads the body
        // by its Content-Length: dart:io sends one of unknown length in chunks, which httpd
        // takes for no body at all (400 «Empty body»).
        final body = utf8.encode(json);
        req.headers.contentType = ContentType.json;
        req.contentLength = body.length;
        req.add(body);
      }
      return await req.close().timeout(timeout);
    } on SocketException {
      throw const PanelError(0);
    } on TimeoutException {
      throw const PanelError(0);
    } on HttpException {
      throw const PanelError(0);
    }
  }

  Future<String> _drain(HttpClientResponse res, {required List<int> ok}) async {
    final text = await utf8.decodeStream(res);
    if (ok.contains(res.statusCode)) return text;
    String? code;
    try {
      final body = jsonDecode(text);
      if (body is Map && body['error'] is String) {
        code = body['error'] as String;
      }
    } on FormatException {
      // a plain-text refusal (httpd's own pages)
    }
    throw PanelError(res.statusCode, code);
  }

  Future<void> _connect() async {
    _retry?.cancel();
    if (!_running) return;
    try {
      final socket = await WebSocket.connect(
        endpoint.ws.toString(),
        customClient: _http,
      ).timeout(timeout);
      if (!_running) {
        await socket.close(WebSocketStatus.normalClosure);
        return;
      }
      _socket = socket;
      _heartbeat = false;
      var first = true;
      socket.listen(
        (data) {
          if (data is! String) return;
          _onFrame(data, snapshot: first);
          first = false;
        },
        onDone: () => _closed(socket),
        onError: (_) => _closed(socket),
        cancelOnError: true,
      );
    } on Object {
      _again(busy: false);
    }
  }

  void _onFrame(String data, {required bool snapshot}) {
    final Object? message;
    try {
      message = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (message is! Map<String, Object?>) return;
    if (message.containsKey('_hb')) _heartbeat = true;
    _listen();
    final values = {
      for (final e in message.entries)
        if (!e.key.startsWith('_')) e.key: e.value,
    };
    if (snapshot) {
      _state = Map.unmodifiable(values);
      _known = true;
      _attempt = 0;
      _status = LinkStatus.ready;
    } else if (values.isNotEmpty) {
      _state = Map.unmodifiable({..._state, ...values});
    } else {
      return;
    }
    _emit();
  }

  /// A socket that has carried a heartbeat and then says nothing for [silence] is gone, whatever
  /// the network stack thinks.
  void _listen() {
    _quiet?.cancel();
    if (!_heartbeat) return;
    final socket = _socket;
    _quiet = Timer(silence, () => socket?.close(4000, 'silent'));
  }

  void _closed(WebSocket socket) {
    if (!identical(socket, _socket)) return;
    _socket = null;
    _quiet?.cancel();
    _again(busy: socket.closeCode == 1013);
  }

  void _again({required bool busy}) {
    if (!_running) return;
    final wait = busy
        ? busyRetry
        : _jitter(backoff[min(_attempt++, backoff.length - 1)]);
    final status = busy ? LinkStatus.busy : LinkStatus.connecting;
    if (status != _status) {
      _status = status;
      _emit();
    }
    _retry = Timer(wait, _connect);
  }

  Duration _jitter(Duration d) => d * (0.8 + 0.4 * _random.nextDouble());

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }
}
