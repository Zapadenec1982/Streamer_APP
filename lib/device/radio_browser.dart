import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'stations.dart';

/// A station of the Radio Browser catalogue, as the app lists it.
class CatalogStation {
  const CatalogStation({
    required this.name,
    required this.url,
    this.uuid = '',
    this.favicon = '',
    this.codec = '',
    this.bitrate = 0,
    this.countryCode = '',
    this.clicks = 0,
    this.votes = 0,
    this.tags = '',
  });

  final String name;

  /// The stream, resolved.
  final String url;
  final String uuid;

  /// The station's logo, or ''.
  final String favicon;
  final String codec;

  /// kbit/s; 0 where the catalogue does not say.
  final int bitrate;
  final String countryCode;

  /// Listens a day.
  final int clicks;
  final int votes;

  /// Comma-separated.
  final String tags;
}

/// What to list: a country's stations, a genre's (a Radio Browser tag), or those whose name has
/// these words.
sealed class CatalogQuery {
  const CatalogQuery();
}

final class ByCountry extends CatalogQuery {
  const ByCountry(this.code);

  final String code;
}

final class ByTag extends CatalogQuery {
  const ByTag(this.tag);

  final String tag;
}

final class ByName extends CatalogQuery {
  const ByName(this.words);

  final String words;
}

/// The order, as the web's chips give it: listened, voted, best stream, by name.
enum CatalogSort {
  popular('&order=clickcount&reverse=true'),
  votes('&order=votes&reverse=true'),
  quality('&order=bitrate&reverse=true'),
  name('&order=name');

  const CatalogSort(this.query);

  final String query;
}

/// The quality floor: any stream, from 128, 192 or 320 kbit/s, or lossless only.
enum CatalogFloor {
  all('', 0),
  k128('&bitrateMin=128', 128),
  k192('&bitrateMin=192', 192),
  k320('&bitrateMin=320', 320),
  flac('&codec=FLAC', 0);

  const CatalogFloor(this.query, this.kbps);

  final String query;
  final int kbps;
}

class CatalogError implements Exception {
  const CatalogError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Radio Browser from the phone (api.radio-browser.info: no key), as the web asks it from the
/// browser (webui/src/lib/radiobrowser.js). The rules are the panel's own (components/
/// radio_catalog: keep(), search_path()): MP3, AAC, AAC+ and FLAC, no HLS, a stream that fits the
/// station list, the quality floor, one row per stream. The panel gets only a station's name,
/// stream and uuid (`radio.web_*`). The station list asks here too, for its stations' logos.
class RadioBrowser {
  RadioBrowser({this._base, Uri? servers})
    : _servers =
          servers ??
          Uri.parse('https://all.api.radio-browser.info/json/servers');

  /// Rows a page.
  static const limit = 50;
  static const _fallback = 'https://de1.api.radio-browser.info';
  static const _playable = {'MP3', 'AAC', 'AAC+', 'FLAC'};
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final Uri _servers;
  String? _base;
  final _http = HttpClient()
    // the catalogue asks its clients to say who they are
    ..userAgent = 'ModESP-Streamer-app/0.1'
    ..connectionTimeout = const Duration(seconds: 8);

  /// Lower-case uuid → logo, '' where the catalogue lists none; for as long as the app runs.
  final _icons = <String, String>{};
  Future<void> _lookup = Future.value();

  Future<Object?> _get(String path) async {
    // The server list, not a fixed host: one is left (de1), and that may change.
    final base = _base ??= await _pickServer();
    try {
      final req = await _http
          .getUrl(Uri.parse('$base$path'))
          .timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decodeStream(res);
      if (res.statusCode != 200) throw CatalogError('${res.statusCode}');
      return jsonDecode(text);
    } on SocketException catch (e) {
      throw CatalogError(e.osError?.message ?? e.message);
    } on TimeoutException {
      throw const CatalogError('timeout');
    } on HttpException catch (e) {
      throw CatalogError(e.message);
    } on FormatException {
      throw const CatalogError('format');
    }
  }

  Future<String> _pickServer() async {
    try {
      final req = await _http
          .getUrl(_servers)
          .timeout(const Duration(seconds: 8));
      final list = jsonDecode(await utf8.decodeStream(await req.close()));
      final names = {
        for (final s in list is List ? list : const [])
          if (s is Map &&
              s['name'] is String &&
              (s['name'] as String).isNotEmpty)
            s['name'] as String,
      }.toList();
      if (names.isEmpty) return _fallback;
      return 'https://${names[Random().nextInt(names.length)]}';
    } on Object {
      return _fallback;
    }
  }

  static bool _keep(Map s, CatalogFloor floor) {
    final codec = '${s['codec'] ?? ''}'.toUpperCase();
    final url = '${s['url_resolved'] ?? s['url'] ?? ''}';
    if (!_playable.contains(codec) ||
        s['hls'] == 1 ||
        !RegExp('^https?://').hasMatch(url) ||
        utf8.encode(url).length > StationLimits.url) {
      return false;
    }
    final lossless = codec == 'FLAC';
    return switch (floor) {
      CatalogFloor.all => true,
      CatalogFloor.flac => lossless,
      _ =>
        !lossless &&
            (s['bitrate'] is int ? s['bitrate'] as int : 0) >= floor.kbps,
    };
  }

  /// One page of stations, filtered and without repeats; [more] where the catalogue has another.
  /// [uaOnly] narrows a genre or a search to Ukraine.
  Future<({List<CatalogStation> rows, bool more})> stations(
    CatalogQuery query, {
    CatalogSort sort = CatalogSort.popular,
    CatalogFloor floor = CatalogFloor.k128,
    bool uaOnly = false,
    int offset = 0,
  }) async {
    final q = StringBuffer('/json/stations/search?hidebroken=true');
    switch (query) {
      case ByCountry(:final code):
        q.write('&countrycode=${Uri.encodeQueryComponent(code)}');
      case ByTag(:final tag):
        q.write('&tag=${Uri.encodeQueryComponent(tag)}');
        if (uaOnly) q.write('&countrycode=UA');
      case ByName(:final words):
        q.write('&name=${Uri.encodeQueryComponent(words)}');
        if (uaOnly) q.write('&countrycode=UA');
    }
    q.write('${sort.query}${floor.query}&limit=$limit&offset=$offset');
    final raw = await _get('$q');
    final list = raw is List ? raw : const [];
    final seen = <String>{};
    final rows = <CatalogStation>[];
    for (final s in list) {
      if (s is! Map || !_keep(s, floor)) continue;
      final url = '${s['url_resolved'] ?? s['url']}';
      if (!seen.add(url.split('?').first)) continue;
      final name = '${s['name'] ?? ''}'.trim();
      int number(String k) => s[k] is int ? s[k] as int : 0;
      rows.add(
        CatalogStation(
          name: name.isEmpty ? url : name,
          url: url,
          uuid: '${s['stationuuid'] ?? ''}',
          favicon: '${s['favicon'] ?? ''}',
          codec: '${s['codec'] ?? ''}'.toUpperCase(),
          bitrate: number('bitrate'),
          countryCode: '${s['countrycode'] ?? ''}',
          clicks: number('clickcount'),
          votes: number('votes'),
          tags: '${s['tags'] ?? ''}',
        ),
      );
    }
    return (rows: rows, more: list.length >= limit);
  }

  /// Countries with stations, Ukraine first, then by how many.
  Future<List<({String code, int count})>> countries() async {
    final raw = await _get(
      '/json/countrycodes?hidebroken=true&order=stationcount&reverse=true',
    );
    final byCode = <String, int>{};
    for (final c in raw is List ? raw : const []) {
      if (c is! Map) continue;
      final code = '${c['name'] ?? ''}'.toUpperCase();
      final n = c['stationcount'] is int ? c['stationcount'] as int : 0;
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(code) || n == 0) continue;
      // "gr" and "GR" are one
      byCode[code] = (byCode[code] ?? 0) + n;
    }
    final out = [for (final e in byCode.entries) (code: e.key, count: e.value)];
    out.sort(
      (a, b) => a.code == 'UA'
          ? -1
          : b.code == 'UA'
          ? 1
          : b.count.compareTo(a.count),
    );
    return out;
  }

  /// The logos of these stations by their uuids: uuid → logo, '' for none. Each uuid is asked
  /// once while the app runs — the ones not yet known in one request — and lookups go one at a
  /// time, so a second waits for the first's answers instead of asking again. A malformed uuid is
  /// never sent and gets no entry; a failed request keeps nothing, so the next call asks again.
  Future<Map<String, String>> favicons(Iterable<String> uuids) {
    final ask = uuids.toList();
    final run = _lookup.then((_) => _lookUp(ask));
    _lookup = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<Map<String, String>> _lookUp(List<String> uuids) async {
    final ask = {
      for (final u in uuids)
        if (_uuid.hasMatch(u) && !_icons.containsKey(u.toLowerCase()))
          u.toLowerCase(),
    };
    if (ask.isNotEmpty) {
      // the panel's own lookup (radio_catalog byuuid_path): every station in one request
      final rows = await _get('/json/stations/byuuid?uuids=${ask.join(',')}');
      final found = <String, String>{for (final u in ask) u: ''};
      for (final r in rows is List ? rows : const []) {
        if (r is! Map) continue;
        final u = '${r['stationuuid'] ?? ''}'.toLowerCase();
        final icon = '${r['favicon'] ?? ''}';
        if (found.containsKey(u) && RegExp('^https?://').hasMatch(icon)) {
          found[u] = icon;
        }
      }
      _icons.addAll(found);
    }
    return {
      for (final u in uuids)
        if (_icons.containsKey(u.toLowerCase())) u: _icons[u.toLowerCase()]!,
    };
  }

  void close() => _http.close(force: true);
}
