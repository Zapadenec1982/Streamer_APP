import 'dart:async';

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
  DemoDeviceApi({bool autoTick = true}) {
    _current = _build();
    if (autoTick) {
      _timer = Timer.periodic(_second, (_) => tick(_second));
    }
  }

  static const panelName = 'ModESP';
  static const phoneName = 'Phone';
  static const stationCount = 12;
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
  void dispose() {
    _timer?.cancel();
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
        playingTitle ??
            const LineLabel(CatalogLine.stations, count: stationCount),
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
