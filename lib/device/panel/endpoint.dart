import 'dart:convert';

/// Where a panel answers, and the login its HTTP API asks for when the login is on.
class PanelEndpoint {
  const PanelEndpoint(this.host, {this.port = 80, this.user, this.password});

  /// A name ("modesp-2c4c.local") or an address, as a person typed or the network announced it.
  final String host;
  final int port;
  final String? user;
  final String? password;

  /// "host" or "host:port", as a person would type it back.
  String get address => port == 80 ? host : '$host:$port';

  Uri http(String path, [Map<String, String>? query]) => Uri(
    scheme: 'http',
    host: host,
    port: port,
    path: path,
    queryParameters: query,
  );

  Uri get ws => Uri(scheme: 'ws', host: host, port: port, path: '/ws');

  /// The Basic credentials (the firmware's NETWORK.md, "Authentication"), or null without a login.
  String? get authorization => user == null
      ? null
      : 'Basic ${base64.encode(utf8.encode('$user:${password ?? ''}'))}';

  PanelEndpoint withLogin(String user, String password) =>
      PanelEndpoint(host, port: port, user: user, password: password);

  PanelEndpoint withoutLogin() => PanelEndpoint(host, port: port);

  /// An address as a person types it: "192.168.1.216", "modesp-2c4c.local", "host:8080",
  /// "http://host/". Null when it is not one.
  static PanelEndpoint? parse(String text) {
    final s = text.trim();
    if (s.isEmpty) return null;
    final uri = Uri.tryParse(s.contains('://') ? s : 'http://$s');
    if (uri == null || uri.host.isEmpty || uri.host.contains(' ')) return null;
    return PanelEndpoint(uri.host, port: uri.hasPort ? uri.port : 80);
  }
}
