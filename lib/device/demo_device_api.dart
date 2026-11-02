import 'dart:async';
import 'dart:typed_data';

import 'device_api.dart';
import 'models.dart';

class _Track {
  const _Track(this.title, this.artist, this.duration);

  final String title;
  final String artist;
  final Duration duration;
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
  static const cardTrackCount = 248;

  static const _second = Duration(seconds: 1);
  static const _tuning = Duration(milliseconds: 1500);

  static const _phoneTracks = [
    _Track('Amber Hours', 'Lantern Theory', Duration(minutes: 3, seconds: 42)),
    _Track(
      'Tidewater Static',
      'Northbound Echo',
      Duration(minutes: 4, seconds: 5),
    ),
    _Track(
      'Seven Quiet Rooms',
      'Lantern Theory',
      Duration(minutes: 3, seconds: 18),
    ),
    _Track(
      'Copper Lanterns',
      'Northbound Echo',
      Duration(minutes: 5, seconds: 1),
    ),
  ];
  static const _cardTracks = [
    _Track('Glasshouse', 'Cedar Line', Duration(minutes: 3, seconds: 54)),
    _Track('Low Tide Lamps', 'Cedar Line', Duration(minutes: 3, seconds: 36)),
    _Track('Northern Window', 'Cedar Line', Duration(minutes: 4, seconds: 12)),
  ];
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

  final _changes = StreamController<DeviceSnapshot>.broadcast();
  Timer? _timer;
  late DeviceSnapshot _current;

  SourceId _source = SourceId.bt;
  int _volume = 32;
  bool _muted = false;
  int _phoneTrack = 0;
  bool _phonePlaying = true;
  Duration _phonePosition = const Duration(seconds: 56);
  int _cardTrack = 0;
  bool _cardPlaying = true;
  Duration _cardPosition = Duration.zero;
  int _station = 0;
  final _presets = [0, 1, 2, -1, -1, -1];
  int _listRev = 1;
  String _sound = 'rock';
  int _eqRev = 1;
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
    if (source == _source) return;
    _source = source;
    if (source == SourceId.radio) _tuningLeft = _tuning;
    _emit();
  }

  @override
  Future<void> transport(TransportAction action) async {
    switch ((_source, action)) {
      case (SourceId.bt, TransportAction.toggle):
        _phonePlaying = !_phonePlaying;
      case (SourceId.bt, _):
        _phoneTrack = _step(_phoneTrack, _phoneTracks.length, action);
        _phonePosition = Duration.zero;
        _phonePlaying = true;
      case (SourceId.card, TransportAction.toggle):
        _cardPlaying = !_cardPlaying;
      case (SourceId.card, _):
        _cardTrack = _step(_cardTrack, _cardTracks.length, action);
        _cardPosition = Duration.zero;
        _cardPlaying = true;
      case (SourceId.radio, TransportAction.previous || TransportAction.next):
        _station = _step(_station, _stations.length, action);
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
      if (_cardPosition >= _cardTracks[_cardTrack].duration) {
        _cardTrack = (_cardTrack + 1) % _cardTracks.length;
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
  Future<SoundPresets> soundPresets() async =>
      SoundPresets(rev: _eqRev, preset: _sound, presets: _sounds);

  @override
  Future<void> chooseSound(String id) async {
    if (id == _sound || !_sounds.contains(id)) return;
    _sound = id;
    _eqRev++;
    _emit();
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
  Future<StationList> stations() async => StationList(
    rev: _listRev,
    stations: [
      for (final (name, _) in _stations)
        Station(name: name, url: 'http://demo.invalid/$name'),
    ],
    presets: List.of(_presets),
  );

  @override
  Future<void> listen(int index) async {
    if (index < 0 || index >= _stations.length || index == _station) return;
    _station = index;
    _tuningLeft = _tuning;
    _emit();
  }

  @override
  Future<void> storePreset(int slot) async {
    if (slot < 0 || slot >= _presets.length) return;
    _presets[slot] = _station;
    _listRev++;
    _emit();
  }

  @override
  Future<void> keepStation() async {}

  /// The demo has no web interface.
  @override
  Uri? web(String route) => null;

  /// The demo draws its own covers (CoverArt).
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
    return DeviceSnapshot(
      name: panelName,
      scheme: 0,
      now: now,
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
      sound: SoundState(
        bass: _bass,
        treble: _treble,
        loudness: _loudness,
        eqOn: _eqOn,
        leveler: _leveler,
        eqRev: _eqRev,
      ),
      radio: StationState(
        current: _station,
        count: _stations.length,
        listRev: _listRev,
        storable: true,
      ),
    );
  }

  bool _isActive(SourceCard card) =>
      card != SourceCard.servers && card.source == _source;

  Label _status(SourceCard card, NowPlaying now) {
    final playingTitle = _isActive(card) && now.playing ? _plain(now) : null;
    return switch (card) {
      SourceCard.bt => playingTitle ?? const LineLabel(CatalogLine.phoneOn),
      SourceCard.airplay => const LineLabel(CatalogLine.airplayWait),
      SourceCard.radio =>
        playingTitle ?? LineLabel(CatalogLine.stations, count: stationCount),
      SourceCard.card =>
        playingTitle ??
            const LineLabel(CatalogLine.tracks, count: cardTrackCount),
      SourceCard.servers => const LineLabel(CatalogLine.servers),
      SourceCard.usb => const LineLabel(CatalogLine.usbWait),
    };
  }

  /// The card's line while its source plays: what plays, in the panel's own words.
  static Label? _plain(NowPlaying now) => switch ((now.title, now.subtitle)) {
    (TextLabel(:final text), TextLabel(text: final sub))
        when now.source == SourceId.radio =>
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
          coverKey: '${t.artist}/${t.title}',
        );
      case SourceId.card:
        final t = _cardTracks[_cardTrack];
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
          coverKey: '${t.artist}/${t.title}',
        );
      case SourceId.radio:
        final (name, line) = _stations[_station];
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
