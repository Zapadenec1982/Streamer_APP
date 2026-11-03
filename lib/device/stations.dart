import 'dart:convert';

import 'models.dart';

/// The station list as the web edits it: a port of the firmware's webui/src/lib/stations.js
/// (GET and POST /api/stations, modules/radio/src/stations_http.inc). The panel keeps the list;
/// the app reads it with its generation, edits a copy, and sends the whole list back with that
/// generation in front. A list that moved meanwhile — a preset stored on the glass — is answered
/// 409 and nothing is lost.
///
/// The limits are the panel's (components/stations/include/stations.h): 64 stations, a name of
/// 63 bytes, a URL of 223 bytes, six presets holding a station's place or −1.
abstract final class StationLimits {
  static const stations = 64;
  static const name = 63;
  static const url = 223;
}

/// Why a stream cannot go into the list.
enum Refusal {
  /// Not an http:// or https:// address.
  url,

  /// Longer than the panel keeps.
  urlLong,

  /// The list has it already.
  duplicate,

  /// The list has its 64.
  full,
}

/// The name cut to the panel's 63 bytes of UTF-8, at a character, never inside one.
String fitName(String name) {
  var runes = name.trim().runes.toList();
  while (utf8.encode(String.fromCharCodes(runes)).length > StationLimits.name) {
    runes = runes.sublist(0, runes.length - 1);
  }
  return String.fromCharCodes(runes);
}

/// Where a stream comes from, as the list's second line says it: the host and any port.
String streamHost(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

/// Edits: each gives a new list, the presets following their stations.
extension StationEdits on StationList {
  StationList _with(List<Station> stations, List<int> presets) =>
      StationList(rev: rev, stations: stations, presets: presets);

  StationList remove(int i) => _with(
    [
      for (var k = 0; k < stations.length; k++)
        if (k != i) stations[k],
    ],
    [for (final p in presets) p == i ? -1 : (p > i ? p - 1 : p)],
  );

  StationList move(int i, int j) {
    if (j < 0 || j >= stations.length || i == j) return this;
    final order = [for (var k = 0; k < stations.length; k++) k];
    order.insert(j, order.removeAt(i));
    final where = {for (var k = 0; k < order.length; k++) order[k]: k};
    return _with(
      [for (final old in order) stations[old]],
      [for (final p in presets) p >= 0 ? where[p]! : -1],
    );
  }

  StationList rename(int i, String name) => _with([
    for (var k = 0; k < stations.length; k++)
      k == i
          ? Station(
              name: fitName(name),
              url: stations[k].url,
              uuid: stations[k].uuid,
            )
          : stations[k],
  ], presets);

  /// Station [i] onto preset [slot], or off every preset with slot −1.
  StationList setPreset(int i, int slot) => _with(stations, [
    for (var k = 0; k < presets.length; k++)
      k == slot ? i : (slot < 0 && presets[k] == i ? -1 : presets[k]),
  ]);

  /// Why a stream cannot be added, or null.
  Refusal? refuse(String url) {
    if (!RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(url)) {
      return Refusal.url;
    }
    if (utf8.encode(url).length > StationLimits.url) return Refusal.urlLong;
    if (stations.any((s) => s.url == url)) return Refusal.duplicate;
    if (stations.length >= StationLimits.stations) return Refusal.full;
    return null;
  }

  StationList add(String name, String url, {String uuid = ''}) {
    final label = fitName(name);
    return _with([
      ...stations,
      Station(
        name: label.isEmpty ? streamHost(url) : label,
        url: url,
        uuid: uuid,
      ),
    ], presets);
  }

  /// The body POST /api/stations takes: the generation first — the panel reads it off the front.
  Map<String, Object?> toJson() => {
    'rev': rev,
    'stations': [
      for (final s in stations)
        {'name': s.name, 'url': s.url, if (s.uuid.isNotEmpty) 'uuid': s.uuid},
    ],
    'presets': presets,
  };
}

/// Stations in an .m3u, .m3u8 or .pls file, as the web's stations.js parsePlaylist reads them:
/// their names, '' where the file gives none, and their streams.
List<({String name, String url})> parsePlaylist(String text) {
  final out = <({String name, String url})>[];
  final lines = [for (final l in text.split(RegExp(r'\r?\n'))) l.trim()];
  if (RegExp(
    r'^\[playlist\]',
    caseSensitive: false,
  ).hasMatch(lines.firstOrNull ?? '')) {
    final files = <String, String>{};
    final titles = <String, String>{};
    for (final l in lines) {
      final file = RegExp(
        r'^File(\d+)=(.+)$',
        caseSensitive: false,
      ).firstMatch(l);
      if (file != null) files[file[1]!] = file[2]!.trim();
      final title = RegExp(
        r'^Title(\d+)=(.+)$',
        caseSensitive: false,
      ).firstMatch(l);
      if (title != null) titles[title[1]!] = title[2]!.trim();
    }
    // in the order the web's Object.keys gives them: whole numbers ascending, then the rest
    bool index(String k) =>
        k == '0' ||
        (!k.startsWith('0') &&
            (k.length < 10 || (k.length == 10 && int.parse(k) < 4294967295)));
    final keys = [
      ...files.keys.where(index).toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b))),
      ...files.keys.where((k) => !index(k)),
    ];
    for (final k in keys) {
      out.add((name: titles[k] ?? '', url: files[k]!));
    }
    return out;
  }
  var name = '';
  for (final l in lines) {
    if (l.isEmpty) continue;
    if (RegExp('^#EXTINF:', caseSensitive: false).hasMatch(l)) {
      name = l
          .replaceFirst(RegExp('^#EXTINF:[^,]*,?', caseSensitive: false), '')
          .trim();
    } else if (!l.startsWith('#')) {
      out.add((name: name, url: l));
      name = '';
    }
  }
  return out;
}

/// The list as an .m3u, as the web's toM3u writes it.
String toM3u(List<Station> stations) {
  final lines = [
    '#EXTM3U',
    for (final s in stations) ...['#EXTINF:-1,${s.name}', s.url],
  ];
  return '${lines.join('\n')}\n';
}

/// A playlist into the list: each stream the list can take, after the ones it has; how many came.
({StationList list, int added}) importPlaylist(
  StationList list,
  List<({String name, String url})> entries,
) {
  var next = list;
  var added = 0;
  for (final e in entries) {
    if (next.refuse(e.url) != null) continue;
    next = next.add(e.name, e.url);
    added++;
  }
  return (list: next, added: added);
}
