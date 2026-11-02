import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'panel/endpoint.dart';
import 'panel/panel_link.dart';

/// The board a ModESP Streamer panel names in `GET /api/ota`.
const playerBoard = 'modesp_p4_player';

/// A panel answering at an address: the firmware's public `GET /api/ota` names its board.
Future<bool> isPanel(PanelEndpoint endpoint) async {
  final link = PanelLink(endpoint, timeout: const Duration(seconds: 4));
  try {
    final ota = await link.getJson('/api/ota');
    return ota is Map && ota['board'] == playerBoard;
  } on Object {
    return false;
  } finally {
    await link.dispose();
  }
}

/// A panel found on the network.
class FoundPanel {
  const FoundPanel({
    required this.id,
    required this.name,
    required this.endpoint,
  });

  /// The mDNS host name without ".local" ("modesp-2c4c"), or the address.
  final String id;
  final String name;
  final PanelEndpoint endpoint;
}

/// Panels on the network. Today's firmware announces `_http._tcp` as «ModESP Controller» on host
/// `modesp-xxxx` (the firmware's NETWORK.md, "Device name and mDNS"); what answers there is
/// checked with [isPanel], since an announcement is not proof.
class PanelDiscovery {
  final _found = StreamController<FoundPanel>.broadcast();
  final _seen = <String>{};
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  Stream<FoundPanel> get found => _found.stream;

  Future<void> start() async {
    final discovery = BonsoirDiscovery(type: '_http._tcp');
    _discovery = discovery;
    await discovery.initialize();
    _sub = discovery.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent(:final service)
            when _looksLikePanel(service):
          service.resolve(discovery.serviceResolver);
        case BonsoirDiscoveryServiceResolvedEvent(:final service):
          unawaited(_check(service));
        default:
      }
    });
    await discovery.start();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    await _discovery?.stop();
    _discovery = null;
  }

  Future<void> dispose() async {
    await stop();
    await _found.close();
  }

  static bool _looksLikePanel(BonsoirService s) =>
      s.name.toLowerCase().startsWith('modesp') ||
      (s.hostname ?? '').toLowerCase().startsWith('modesp');

  Future<void> _check(BonsoirService s) async {
    final hostname = (s.hostname ?? '').replaceFirst(
      RegExp(r'\.local\.?$'),
      '',
    );
    // an address the phone already resolved: Android cannot always resolve .local itself
    final address = s.hostAddresses.firstWhere(
      (a) => !a.contains(':'),
      orElse: () => '',
    );
    final host = address.isNotEmpty ? address : (s.hostname ?? '');
    if (host.isEmpty) return;
    final id = hostname.isNotEmpty ? hostname : host;
    if (!_seen.add(id)) return;
    final endpoint = PanelEndpoint(host, port: s.port);
    if (await isPanel(endpoint)) {
      if (!_found.isClosed) {
        _found.add(FoundPanel(id: id, name: s.name, endpoint: endpoint));
      }
    } else {
      _seen.remove(id);
    }
  }
}
