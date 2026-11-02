import 'dart:convert';

import 'panel/endpoint.dart';

/// A panel the app has been connected to.
class SavedPanel {
  const SavedPanel({
    required this.id,
    required this.name,
    required this.host,
    this.port = 80,
  });

  /// The panel's mDNS host name ("modesp-2c4c") when it is known, else the address it was added by.
  final String id;

  /// The panel's device name, as it last said it.
  final String name;
  final String host;
  final int port;

  PanelEndpoint get endpoint => PanelEndpoint(host, port: port);

  String get address => endpoint.address;

  SavedPanel copyWith({String? name, String? host, int? port}) => SavedPanel(
    id: id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
  };

  static SavedPanel? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'],
        name = json['name'],
        host = json['host'],
        port = json['port'];
    if (id is! String || name is! String || host is! String) return null;
    return SavedPanel(
      id: id,
      name: name,
      host: host,
      port: port is int ? port : 80,
    );
  }

  static List<SavedPanel> listFromJson(String? text) {
    if (text == null) return const [];
    try {
      final list = jsonDecode(text);
      return list is List
          ? list.map(fromJson).whereType<SavedPanel>().toList()
          : const [];
    } on FormatException {
      return const [];
    }
  }

  static String listToJson(List<SavedPanel> panels) =>
      jsonEncode([for (final p in panels) p.toJson()]);
}

/// Which panel the app shows: one of the saved ones, the demo, or none yet.
sealed class PanelChoice {
  const PanelChoice();

  static const demoId = 'demo';

  /// As kept in the settings: a saved panel's id, [demoId], or null.
  String? get id;
}

final class NoPanel extends PanelChoice {
  const NoPanel();

  @override
  String? get id => null;
}

final class DemoPanel extends PanelChoice {
  const DemoPanel();

  @override
  String get id => PanelChoice.demoId;
}

final class RealPanel extends PanelChoice {
  const RealPanel(this.panel);

  final SavedPanel panel;

  @override
  String get id => panel.id;
}

/// A panel's login, kept in the phone's secure storage and never in the settings or a log.
class PanelLogin {
  const PanelLogin(this.user, this.password);

  final String user;
  final String password;

  String toJson() => jsonEncode({'user': user, 'password': password});

  static PanelLogin? fromJson(String? text) {
    if (text == null) return null;
    try {
      final m = jsonDecode(text);
      return m is Map && m['user'] is String && m['password'] is String
          ? PanelLogin(m['user'] as String, m['password'] as String)
          : null;
    } on FormatException {
      return null;
    }
  }
}
