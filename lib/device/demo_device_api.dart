import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'demo_art.dart';
import 'device_api.dart';
import 'eq.dart';
import 'media.dart';
import 'models.dart';

class _Track {
  const _Track(
    this.title,
    this.artist,
    this.seconds,
    this.art, {
    this.album,
    this.rel,
  });

  final String title;
  final String artist;
  final int seconds;

  /// Its cover: a [DemoArt] palette and pattern — the album's, for one of the card's.
  final (int, int) art;

  /// The card's: its album, and its path under the card's root.
  final String? album;
  final String? rel;

  Duration get duration => Duration(seconds: seconds);

  String get coverKey => DemoArt.key(art.$1, art.$2, album ?? title);
}

/// A media server's entry: a folder, or a track.
class _Node {
  const _Node.folder(this.title, this.children)
    : folder = true,
      artist = '',
      art = (0, 0),
      playable = false;

  const _Node.track(this.title, this.artist, this.art, {this.playable = true})
    : folder = false,
      children = const [];

  final String title;
  final bool folder;
  final List<_Node> children;
  final String artist;
  final (int, int) art;
  final bool playable;
}

/// A made-up panel, so the app can be seen without one — by a store's reviewer, and while it is
/// being built. Every title and name here is invented for the demo.
class DemoDeviceApi implements DeviceApi {
  DemoDeviceApi({this.autoTick = true}) {
    _current = _build();
    resume();
  }

  /// Time passes by itself (once a second); tests turn that off and call [tick].
  final bool autoTick;

  static const panelName = 'ModESP';
  static const phoneName = 'Phone';
  static int get stationCount => _stations.length;
  static int get cardTrackCount => _cardTracks.length;

  /// Where the card's tracks are, as `GET /api/library` names it.
  static const cardRoot = '/sdcard';

  static const _second = Duration(seconds: 1);
  static const _tuning = Duration(milliseconds: 1500);

  static const _phoneTracks = [
    _Track('Amber Hours', 'Lantern Theory', 222, (0, 0)),
    _Track('Tidewater Static', 'Northbound Echo', 245, (1, 3)),
    _Track('Seven Quiet Rooms', 'Lantern Theory', 198, (2, 2)),
    _Track('Copper Lanterns', 'Northbound Echo', 301, (3, 1)),
  ];

  /// The card: the demo's own albums, a folder each under the card's root.
  static const _albums = [
    (
      'Cedar Line',
      'Northern Window',
      (5, 3),
      [
        ('Glasshouse', 234),
        ('Low Tide Lamps', 216),
        ('Northern Window', 252),
        ('Paper Harbour', 201),
        ('Slow Weather', 243),
      ],
    ),
    (
      'Lantern Theory',
      'Amber Hours',
      (0, 0),
      [
        ('Amber Hours', 222),
        ('Seven Quiet Rooms', 198),
        ('Morning Static', 231),
        ('The Long Hallway', 264),
      ],
    ),
    (
      'Northbound Echo',
      'Copper Lanterns',
      (3, 1),
      [
        ('Tidewater Static', 245),
        ('Copper Lanterns', 301),
        ('Salt Roads', 219),
      ],
    ),
    (
      'Glass Orchard',
      'Field Notes',
      (4, 2),
      [
        ('Greenhouse Light', 207),
        ('Field Notes', 233),
        ('Last Ferry', 256),
        ('Orchard Road', 198),
      ],
    ),
  ];
  static final List<_Track> _cardTracks = [
    for (final (artist, album, art, tracks) in _albums)
      for (final (i, (title, seconds)) in tracks.indexed)
        _Track(
          title,
          artist,
          seconds,
          art,
          album: album,
          rel: '$artist/$album/${'${i + 1}'.padLeft(2, '0')} $title.flac',
        ),
  ];

  /// The media servers on the demo's network, with folders and tracks of its own.
  static const _servers = [
    _Node.folder('Attic NAS', [
      _Node.folder('Music', [
        _Node.folder('Glass Orchard', [
          _Node.folder('Field Notes', [
            _Node.track('Greenhouse Light', 'Glass Orchard', (4, 2)),
            _Node.track('Field Notes', 'Glass Orchard', (4, 2)),
            _Node.track('Last Ferry', 'Glass Orchard', (4, 2)),
            _Node.track('Orchard Road', 'Glass Orchard', (4, 2)),
          ]),
        ]),
        _Node.folder('Lantern Theory', [
          _Node.folder('Amber Hours', [
            _Node.track('Amber Hours', 'Lantern Theory', (0, 0)),
            _Node.track('Seven Quiet Rooms', 'Lantern Theory', (0, 0)),
            _Node.track('Morning Static', 'Lantern Theory', (0, 0)),
          ]),
        ]),
      ]),
      _Node.folder('Live Recordings', [
        _Node.track('Harbour Session', 'Northbound Echo', (
          3,
          1,
        ), playable: false),
      ]),
    ]),
    _Node.folder('Living Room PC', [
      _Node.folder('Audio', [
        _Node.track('Paper Harbour', 'Cedar Line', (5, 3)),
        _Node.track('Slow Weather', 'Cedar Line', (5, 3)),
      ]),
    ]),
  ];

  /// Rows a page, as the panel's browser asks a server for them.
  static const _browsePage = 12;
  static const _stations = [
    ('Radio Lantern', 'Lantern Theory - Amber Hours'),
    ('Northbound FM', 'Northbound Echo - Tidewater Static'),
    ('Cedar Jazz', 'Cedar Line - Glasshouse'),
    ('Harbour Lights FM', 'Lantern Theory - Seven Quiet Rooms'),
    ('Amber Wave', 'Northbound Echo - Copper Lanterns'),
    ('Low Tide Radio', 'Cedar Line - Low Tide Lamps'),
    ('Copper Street', 'Lantern Theory - Amber Hours'),
    ('Glasshouse Radio', 'Cedar Line - Northern Window'),
    ('Quiet Engines FM', 'Northbound Echo - Tidewater Static'),
    ('Night Shift Radio', 'Lantern Theory - Seven Quiet Rooms'),
    ('Salt and Cedar', 'Cedar Line - Glasshouse'),
    ('Eastern Window', 'Northbound Echo - Copper Lanterns'),
  ];

  /// The sounds the panel offers (eq_presets.cpp's eight).
  static const _sounds = [
    'custom',
    'flat',
    'pop',
    'rock',
    'jazz',
    'classical',
    'electronic',
    'hiphop',
  ];

  /// The presets' bands (eq_presets.cpp): a low shelf, eight octave peaks, a high shelf; a 0 dB
  /// band is off.
  static const _presetF = [
    40.0,
    62.5,
    125.0,
    250.0,
    500.0,
    1000.0,
    2000.0,
    4000.0,
    8000.0,
    12000.0,
  ];
  static const _presetGain = {
    'flat': [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    'pop': [-1.4, -1.1, 1.0, 2.7, 3.4, 2.3, 0.2, -1.1, -1.2, -1.0],
    'rock': [4.9, 3.6, 3.1, -0.8, -4.2, -1.8, 0.7, 2.5, 4.5, 7.0],
    'jazz': [3.3, 1.9, 0.5, -0.2, -0.2, 0.7, 1.0, 0.4, 1.3, 3.3],
    'classical': [0.0, 0.0, 0.0, -0.1, -0.2, 0.0, 0.7, -1.0, -3.5, -5.5],
    'electronic': [4.9, 3.4, 3.0, 1.1, -2.3, -2.4, -1.1, 1.3, 4.3, 6.1],
    'hiphop': [5.3, 3.3, 1.8, 0.4, -0.6, -0.1, 0.3, 0.6, 1.0, 2.1],
  };

  static List<EqBand> _presetBands(List<double> gains) => [
    for (var i = 0; i < gains.length; i++)
      EqBand(
        type: i == 0
            ? EqType.lowshelf
            : i == gains.length - 1
            ? EqType.highshelf
            : EqType.peak,
        f: _presetF[i],
        gain: gains[i],
        q: i == 0 || i == gains.length - 1 ? 0.707 : 1,
        on: gains[i].abs() >= 0.05,
      ),
  ];

  final _changes = StreamController<DeviceSnapshot>.broadcast();
  Timer? _timer;
  late DeviceSnapshot _current;

  SourceId _source = SourceId.bt;
  int _volume = 32;
  bool _muted = false;
  int _phoneTrack = 0;
  bool _phonePlaying = true;
  Duration _phonePosition = const Duration(seconds: 56);
  int _cardIndex = 0;
  bool _cardPlaying = true;
  Duration _cardPosition = Duration.zero;
  int _repeat = 0;
  bool _shuffle = false;
  final _random = Random(7);
  bool _found = false;
  final _path = <_Node>[];
  int _page = 0;
  int _browseRev = 1;
  String _browseStatus = '@dlna.st_not_searched';
  _Node? _dlna;
  bool _dlnaPlaying = false;
  int _station = 0;
  final _presets = [0, 1, 2, -1, -1, -1];
  int _listRev = 1;

  /// The station list as it is now: edited, kept and stored into, as the panel's.
  final _list = [
    for (final (name, line) in _stations)
      (name: name, url: 'http://demo.invalid/$name', uuid: '', line: line),
  ];

  /// A catalogue station that plays and is not in the list.
  ({String name, String url, String uuid})? _catalog;
  String _sound = 'rock';
  int _eqRev = 1;

  /// «Власний», kept as it is edited — a set of three, as an import leaves one, so a band can be
  /// added — and the set that plays.
  var _custom = const [
    EqBand(type: EqType.lowshelf, f: 80, gain: 3, q: 0.7),
    EqBand(type: EqType.peak, f: 2500, gain: -1.5, q: 1.4),
    EqBand(type: EqType.highshelf, f: 10000, gain: 2, q: 0.7),
  ];
  var _bands = _presetBands(_presetGain['rock']!);
  int _volMax = 100;
  int _volStart = 0;
  bool _levSchedule = false;
  int _levFrom = 22 * 60;
  int _levTo = 7 * 60;
  int _bass = 2;
  int _treble = 0;
  bool _loudness = true;
  bool _eqOn = true;
  bool _leveler = false;
  Duration _tuningLeft = Duration.zero;

  @override
  DeviceSnapshot get current => _current;

  @override
  Stream<DeviceSnapshot> get changes => _changes.stream;

  @override
  Future<void> setVolume(int percent) async {
    _volume = percent.clamp(0, 100);
    _emit();
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    _emit();
  }

  @override
  Future<void> selectSource(SourceId source) async {
    if (source == _source && _dlna == null) return;
    _source = source;
    _dlna = null;
    if (source == SourceId.radio) _tuningLeft = _tuning;
    _emit();
  }

  @override
  Future<void> transport(TransportAction action) async {
    // a track from a media server rides the radio's source, and has only play and pause here
    if (_dlna != null && _source == SourceId.radio) {
      if (action != TransportAction.toggle) return;
      _dlnaPlaying = !_dlnaPlaying;
      _emit();
      return;
    }
    switch ((_source, action)) {
      case (SourceId.bt, TransportAction.toggle):
        _phonePlaying = !_phonePlaying;
      case (SourceId.bt, _):
        _phoneTrack = _step(_phoneTrack, _phoneTracks.length, action);
        _phonePosition = Duration.zero;
        _phonePlaying = true;
      case (SourceId.card, TransportAction.toggle):
        _cardPlaying = !_cardPlaying;
      case (SourceId.card, TransportAction.next) when _shuffle:
        _cardIndex = _shuffled();
        _cardPosition = Duration.zero;
        _cardPlaying = true;
      case (SourceId.card, _):
        _cardIndex = _step(_cardIndex, _cardTracks.length, action);
        _cardPosition = Duration.zero;
        _cardPlaying = true;
      case (SourceId.radio, TransportAction.previous || TransportAction.next):
        _station = _step(_station, _list.length, action);
        _catalog = null;
        _tuningLeft = _tuning;
      default:
        return;
    }
    _emit();
  }

  /// Time passes: the track moves on, a station finishes tuning. The timer calls it every
  /// second; tests call it themselves.
  void tick(Duration elapsed) {
    var changed = false;
    if (_source == SourceId.bt && _phonePlaying) {
      _phonePosition += elapsed;
      if (_phonePosition >= _phoneTracks[_phoneTrack].duration) {
        _phoneTrack = (_phoneTrack + 1) % _phoneTracks.length;
        _phonePosition = Duration.zero;
      }
      changed = true;
    }
    if (_source == SourceId.card && _cardPlaying) {
      _cardPosition += elapsed;
      if (_cardPosition >= _cardTracks[_cardIndex].duration) {
        _cardIndex = _repeat == 1
            ? _cardIndex
            : _shuffle
            ? _shuffled()
            : (_cardIndex + 1) % _cardTracks.length;
        _cardPosition = Duration.zero;
      }
      changed = true;
    }
    if (_source == SourceId.radio && _tuningLeft > Duration.zero) {
      _tuningLeft -= elapsed;
      changed = true;
    }
    if (changed) _emit();
  }

  @override
  Future<void> seek(int seconds) async {
    if (_source != SourceId.card) return;
    final end = _cardTracks[_cardIndex].seconds;
    _cardPosition = Duration(seconds: seconds.clamp(0, end));
    _emit();
  }

  @override
  Future<void> setRepeat(int mode) async {
    _repeat = mode.clamp(0, 2);
    _emit();
  }

  @override
  Future<void> setShuffle(bool on) async {
    _shuffle = on;
    _emit();
  }

  @override
  Future<LibraryPage> library({int from = 0, int count = 200}) async {
    final rows = [for (final t in _cardTracks) t.rel!];
    final start = from.clamp(0, rows.length);
    return LibraryPage(
      gen: 1,
      busy: false,
      count: rows.length,
      cursor: _cardIndex,
      root: cardRoot,
      from: start,
      rows: rows.sublist(start, min(start + count, rows.length)),
    );
  }

  @override
  Future<void> playTrack(String path) async {
    final i = _cardTracks.indexWhere(
      (t) => trackPath(cardRoot, t.rel!) == path,
    );
    if (i < 0) return;
    _source = SourceId.card;
    _dlna = null;
    _cardIndex = i;
    _cardPosition = Duration.zero;
    _cardPlaying = true;
    _emit();
  }

  /// The folder on screen: the server, then each folder opened under it.
  List<_Node> get _rows =>
      _path.isEmpty ? (_found ? _servers : const []) : _path.last.children;

  @override
  Future<DlnaView> dlnaView() async {
    final all = _rows;
    final start = _path.isEmpty ? 0 : _page * _browsePage;
    final page = _path.isEmpty
        ? all
        : all.skip(start).take(_browsePage).toList();
    return DlnaView(
      revision: _browseRev,
      busy: false,
      servers: _path.isEmpty,
      canBack: _path.isNotEmpty,
      count: page.length,
      next: _path.isNotEmpty && start + _browsePage < all.length,
      previous: _path.isNotEmpty && _page > 0,
      title: _path.isEmpty ? '@dlna.servers' : _path.last.title,
      status: _browseStatus,
      rows: [
        for (final n in page)
          DlnaRow(
            title: n.title,
            artist: n.artist,
            folder: n.folder,
            playable: n.playable,
          ),
      ],
    );
  }

  /// The browser's commands, as dlna_client takes them: one chosen from a snapshot that has moved
  /// on does nothing.
  @override
  Future<void> dlnaCommand(int code) async {
    final command = code & 15, row = code >> 4 & 255;
    if ((code >> 12 & 0xffff) != (_browseRev & 0xffff)) return;
    final view = await dlnaView();
    final rows = _rows;
    final at = (_path.isEmpty ? 0 : _page * _browsePage) + row;
    switch (command) {
      case Browse.discover:
        _found = true;
        _path.clear();
        _page = 0;
        _browseStatus = '@dlna.st_servers\u001fn=${_servers.length}';
      case Browse.open when row < view.count:
        final node = rows[at];
        if (node.folder) {
          _path.add(node);
          _page = 0;
          _browseStatus =
              '@dlna.st_page\u001fn=${min(node.children.length, _browsePage)}';
        } else if (node.playable) {
          _dlna = node;
          _dlnaPlaying = true;
          _source = SourceId.radio;
          _browseStatus = '@dlna.st_playing\u001ftitle=${node.title}';
        } else {
          _browseStatus = '@dlna.unsupported';
        }
      case Browse.back when _path.isNotEmpty:
        _path.removeLast();
        _page = 0;
      case Browse.next when view.next:
        _page++;
      case Browse.previous when view.previous:
        _page--;
      case Browse.queue when row < view.count:
        _browseStatus = '@dlna.queued\u001ftitle=${rows[at].title}';
        _emit();
        return;
      default:
        return;
    }
    _browseRev++;
    _emit();
  }

  int _shuffled() {
    final n = _cardTracks.length;
    return (_cardIndex + 1 + _random.nextInt(n - 1)) % n;
  }

  @override
  Future<EqDoc> eq() async =>
      EqDoc(rev: _eqRev, preset: _sound, presets: _sounds, bands: _bands);

  @override
  Future<void> chooseSound(String id) async {
    if (id == _sound || !_sounds.contains(id)) return;
    _sound = id;
    _bands = id == 'custom' ? _custom : _presetBands(_presetGain[id]!);
    _eqRev++;
    _emit();
  }

  /// A hand edit is «Власний», as the panel's (eq_hand_edited).
  @override
  Future<int> setEqBands(int rev, List<EqBand> bands) async {
    if (rev != _eqRev) throw const EqChanged();
    _custom = _bands = [
      for (final b in bands.take(EqLimits.bands)) b.clamped(),
    ];
    _sound = 'custom';
    _eqRev++;
    _emit();
    return _eqRev;
  }

  @override
  Future<void> keepSound() async {}

  @override
  Future<void> setBass(int db) async {
    _bass = db.clamp(-6, 6);
    _emit();
  }

  @override
  Future<void> setTreble(int db) async {
    _treble = db.clamp(-6, 6);
    _emit();
  }

  @override
  Future<void> setLoudness(bool on) async {
    _loudness = on;
    _emit();
  }

  @override
  Future<void> setEqOn(bool on) async {
    _eqOn = on;
    _emit();
  }

  @override
  Future<void> setLeveler(bool on) async {
    _leveler = on;
    _emit();
  }

  @override
  Future<void> setLevelerSchedule({bool? on, int? from, int? to}) async {
    _levSchedule = on ?? _levSchedule;
    _levFrom = from?.clamp(0, 1435) ?? _levFrom;
    _levTo = to?.clamp(0, 1435) ?? _levTo;
    _emit();
  }

  @override
  Future<void> setVolMax(int percent) async {
    _volMax = percent.clamp(40, 100);
    _emit();
  }

  @override
  Future<void> setVolStart(int percent) async {
    _volStart = percent.clamp(0, 100);
    _emit();
  }

  @override
  Future<StationList> stations() async => StationList(
    rev: _listRev,
    stations: [
      for (final s in _list) Station(name: s.name, url: s.url, uuid: s.uuid),
    ],
    presets: List.of(_presets),
  );

  @override
  Future<void> listen(int index) async {
    if (index < 0 || index >= _list.length) return;
    if (index == _station && _dlna == null && _catalog == null) return;
    _dlna = null;
    _catalog = null;
    _station = index;
    _tuningLeft = _tuning;
    _emit();
  }

  @override
  Future<void> storePreset(int slot) async {
    if (slot < 0 || slot >= _presets.length) return;
    // a catalogue station goes into the list as it goes onto the preset, as on the panel
    final catalog = _catalog;
    if (catalog != null) _keep(catalog.name, catalog.url, catalog.uuid);
    _presets[slot] = _station;
    _listRev++;
    _emit();
  }

  @override
  Future<void> keepStation() async {
    final catalog = _catalog;
    if (catalog == null) return;
    _keep(catalog.name, catalog.url, catalog.uuid);
    _listRev++;
    _emit();
  }

  /// A station into the list, if it is not there; the one that plays becomes it.
  int _keep(String name, String url, String uuid) {
    var i = _list.indexWhere((s) => s.url == url);
    if (i < 0) {
      _list.add((name: name, url: url, uuid: uuid, line: ''));
      i = _list.length - 1;
    }
    if (_catalog?.url == url) {
      _catalog = null;
      _station = i;
    }
    return i;
  }

  /// As the panel: a list edited from an older generation is refused (409).
  @override
  Future<StationsSave> saveStations(StationList edited) async {
    if (edited.rev != _listRev) return StationsSave.changed;
    final playing = _station >= 0 && _station < _list.length
        ? _list[_station].url
        : null;
    final lines = {for (final s in _list) s.url: s.line};
    _list
      ..clear()
      ..addAll([
        for (final s in edited.stations)
          (name: s.name, url: s.url, uuid: s.uuid, line: lines[s.url] ?? ''),
      ]);
    for (var k = 0; k < _presets.length; k++) {
      _presets[k] = k < edited.presets.length ? edited.presets[k] : -1;
    }
    final at = _list.indexWhere((s) => s.url == playing);
    _station = at < 0 ? 0 : at;
    _listRev++;
    _emit();
    return StationsSave.saved;
  }

  @override
  Future<void> catalogStation({
    required String name,
    required String url,
    String uuid = '',
    required int act,
  }) async {
    if (act == 0) {
      final i = _list.indexWhere((s) => s.url == url);
      _source = SourceId.radio;
      _dlna = null;
      _tuningLeft = _tuning;
      if (i >= 0) {
        _catalog = null;
        _station = i;
      } else {
        _catalog = (name: name, url: url, uuid: uuid);
      }
      _emit();
      return;
    }
    final i = _keep(name, url, uuid);
    if (act >= 2 && act <= 7) _presets[act - 2] = i;
    _listRev++;
    _emit();
  }

  /// A few of the panel's genres, the demo's own table.
  @override
  Future<List<Genre>> radioGenres() async => const [
    Genre(
      tag: 'jazz',
      names: {'uk': 'Джаз', 'en': 'Jazz', 'de': 'Jazz', 'pl': 'Jazz'},
    ),
    Genre(
      tag: 'classical',
      names: {
        'uk': 'Класика',
        'en': 'Classical',
        'de': 'Klassik',
        'pl': 'Klasyczna',
      },
    ),
    Genre(
      tag: 'rock',
      names: {'uk': 'Рок', 'en': 'Rock', 'de': 'Rock', 'pl': 'Rock'},
    ),
    Genre(
      tag: 'ambient',
      names: {
        'uk': 'Ембієнт',
        'en': 'Ambient',
        'de': 'Ambient',
        'pl': 'Ambient',
      },
    ),
  ];

  /// The demo has no web interface.
  @override
  Uri? web(String route) => null;

  /// The demo draws its own covers (DemoArt).
  @override
  Future<Uint8List?> cover(String key) async => null;

  @override
  void suspend() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void resume() {
    if (autoTick && _timer == null) {
      _timer = Timer.periodic(_second, (_) => tick(_second));
    }
  }

  @override
  void dispose() {
    suspend();
    _changes.close();
  }

  static int _step(int index, int count, TransportAction action) =>
      (index + (action == TransportAction.previous ? count - 1 : 1)) % count;

  void _emit() {
    _current = _build();
    if (!_changes.isClosed) _changes.add(_current);
  }

  DeviceSnapshot _build() {
    final now = _now();
    final cover = now.coverKey;
    return DeviceSnapshot(
      name: panelName,
      scheme: 0,
      now: now,
      // the Player's background follows the cover, as the panel's does (ui.cover_rgb)
      backdrop: cover != null && now.kind != NowKind.radio
          ? DemoArt.of(cover).backdrop
          : null,
      cards: [
        for (final card in SourceCard.values)
          SourceCardState(
            card,
            active: _isActive(card),
            status: _status(card, now),
          ),
      ],
      volume: _volume,
      muted: _muted,
      cardIndex: _cardIndex,
      cardCount: _cardTracks.length,
      sound: SoundState(
        bass: _bass,
        treble: _treble,
        loudness: _loudness,
        eqOn: _eqOn,
        leveler: _leveler,
        eqRev: _eqRev,
        volMax: _volMax,
        volStart: _volStart,
        levSchedule: _levSchedule,
        levFrom: _levFrom,
        levTo: _levTo,
        // a quiet evening: the loudness lifts the bass as the panel's would
        loudDb: _loudness ? 6 : 0,
      ),
      radio: StationState(
        current: _catalog != null ? -1 : _station,
        count: _list.length,
        listRev: _listRev,
        storable: true,
      ),
    );
  }

  bool _isActive(SourceCard card) => switch (card) {
    SourceCard.servers => _source == SourceId.radio && _dlna != null,
    SourceCard.radio => _source == SourceId.radio && _dlna == null,
    _ => card.source == _source,
  };

  Label _status(SourceCard card, NowPlaying now) {
    final playingTitle = _isActive(card) && now.playing ? _plain(now) : null;
    return switch (card) {
      SourceCard.bt => playingTitle ?? const LineLabel(CatalogLine.phoneOn),
      SourceCard.airplay => const LineLabel(CatalogLine.airplayWait),
      SourceCard.radio =>
        playingTitle ?? LineLabel(CatalogLine.stations, count: _list.length),
      SourceCard.card =>
        playingTitle ?? LineLabel(CatalogLine.tracks, count: cardTrackCount),
      SourceCard.servers =>
        playingTitle ?? const LineLabel(CatalogLine.servers),
      SourceCard.usb => const LineLabel(CatalogLine.usbWait),
    };
  }

  /// The card's line while its source plays: what plays, in the panel's own words.
  static Label? _plain(NowPlaying now) => switch ((now.title, now.subtitle)) {
    (TextLabel(:final text), TextLabel(text: final sub))
        when now.kind == NowKind.radio =>
      TextLabel(sub.isEmpty ? text : sub),
    (TextLabel(:final text), _) => TextLabel(text),
    _ => null,
  };

  NowPlaying _now() {
    switch (_source) {
      case SourceId.bt:
        final t = _phoneTracks[_phoneTrack];
        return NowPlaying(
          kind: NowKind.bt,
          title: TextLabel(t.title),
          subtitle: TextLabel(t.artist),
          device: phoneName,
          format: 'LHDC V5 96.0 kHz',
          playing: _phonePlaying,
          canToggle: true,
          canPrevious: true,
          canNext: true,
          position: _phonePosition,
          duration: t.duration,
          coverKey: t.coverKey,
        );
      case SourceId.card:
        final t = _cardTracks[_cardIndex];
        return NowPlaying(
          kind: NowKind.card,
          title: TextLabel(t.title),
          subtitle: TextLabel(t.artist),
          format: 'FLAC 44.1 kHz 16 bit',
          playing: _cardPlaying,
          canToggle: true,
          canPrevious: true,
          canNext: true,
          position: _cardPosition,
          duration: t.duration,
          coverKey: t.coverKey,
          seekable: true,
          repeat: _repeat,
          shuffle: _shuffle,
        );
      case SourceId.radio when _dlna != null:
        final n = _dlna!;
        return NowPlaying(
          kind: NowKind.dlna,
          title: TextLabel(n.title),
          subtitle: TextLabel(n.artist),
          format: 'FLAC 44.1 kHz 16 bit',
          playing: _dlnaPlaying,
          canToggle: true,
          coverKey: DemoArt.key(n.art.$1, n.art.$2, n.title),
        );
      case SourceId.radio:
        final catalog = _catalog;
        final (name, line) = catalog != null
            ? (catalog.name, '')
            : (_list[_station].name, _list[_station].line);
        final tuning = _tuningLeft > Duration.zero;
        return NowPlaying(
          kind: NowKind.radio,
          title: TextLabel(name),
          subtitle: tuning
              ? const LineLabel(CatalogLine.connecting)
              : TextLabel(line),
          format: tuning ? '' : 'AAC 44.1 kHz 128 kbps',
          playing: true,
          canPrevious: true,
          canNext: true,
          coverKey: name,
        );
      case SourceId.airplay:
        return const NowPlaying(
          kind: NowKind.airplay,
          title: LineLabel(CatalogLine.airplayWaiting),
          subtitle: LineLabel(CatalogLine.airplayPick, name: panelName),
        );
      case SourceId.usb:
        return const NowPlaying(
          kind: NowKind.usb,
          title: LineLabel(CatalogLine.usbWaiting),
          subtitle: LineLabel(CatalogLine.usbPick, name: panelName),
        );
      case SourceId.off || SourceId.tone || SourceId.aux:
        return const NowPlaying(
          kind: NowKind.off,
          title: LineLabel(CatalogLine.off),
          subtitle: LineLabel(CatalogLine.pick),
        );
    }
  }
}
