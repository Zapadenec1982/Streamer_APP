import 'dart:async';
import 'dart:typed_data';

import '../device_api.dart';
import '../eq.dart';
import '../face.dart';
import '../keys.dart';
import '../models.dart';
import '../speakers.dart';
import '../stations.dart';
import 'panel_link.dart';

/// A real panel: its state, heard over [PanelLink], as the app's models, and the app's commands
/// as the panel's keys. Nothing is assumed to have happened until the panel reports it.
class PanelDeviceApi implements DeviceApi {
  PanelDeviceApi(this.link) {
    _current = snapshotOf(link.state, status: link.status, known: link.known);
    _sub = link.changes.listen((_) {
      _current = snapshotOf(link.state, status: link.status, known: link.known);
      if (!_changes.isClosed) _changes.add(_current);
    });
    link.start();
  }

  final PanelLink link;
  final _changes = StreamController<DeviceSnapshot>.broadcast();
  late final StreamSubscription<void> _sub;
  late DeviceSnapshot _current;

  @override
  DeviceSnapshot get current => _current;

  @override
  Stream<DeviceSnapshot> get changes => _changes.stream;

  @override
  Future<void> setVolume(int percent) =>
      link.write({Keys.audioVolume.name: percent.clamp(0, 100)});

  @override
  Future<void> setMuted(bool muted) => link.write({Keys.audioMute.name: muted});

  @override
  Future<void> transport(TransportAction action) async {
    final code = switch (action) {
      TransportAction.toggle => Transport.toggle,
      TransportAction.previous => Transport.previous,
      TransportAction.next => Transport.next,
    };
    // the panel says which codes the source that plays takes now
    if (!Transport.takes(Keys.audioTransportCaps.of(link.state) ?? 0, code)) {
      return;
    }
    await link.write({Keys.audioTransport.name: code});
  }

  @override
  Future<void> seek(int seconds) {
    // where the source that plays takes a position (now.js seekKey)
    final key = face(link.state).seekKey;
    if (key == null) return Future.value();
    return link.write({key: seconds < 0 ? 0 : seconds});
  }

  @override
  Future<void> setRepeat(int mode) =>
      link.write({Keys.playerRepeat.name: mode.clamp(0, 2)});

  @override
  Future<void> setShuffle(bool on) => link.write({Keys.playerShuffle.name: on});

  @override
  Future<LibraryPage> library({int from = 0, int count = 200}) async =>
      libraryOf(
        await link.getJson('/api/library', {'from': '$from', 'n': '$count'}),
      );

  /// The path first, then the command, in one body: the player reads the one with the other.
  @override
  Future<void> playTrack(String path) =>
      link.write({Keys.playerTrack.name: path, Keys.playerCmd.name: 1});

  @override
  Future<DlnaView> dlnaView() async =>
      dlnaViewOf(await link.getJson('/api/dlna/browser'));

  @override
  Future<void> dlnaCommand(int code) =>
      link.write({Keys.dlnaBrowseCmd.name: code});

  @override
  Future<void> selectSource(SourceId source) => link.write({
    Keys.audioSource.name: source.value,
    // the radio plays as it is chosen, as the glass and the web do (screen_src.cpp)
    if (source == SourceId.radio) Keys.radioCmd.name: 1,
  });

  @override
  Future<EqDoc> eq() async => EqDoc.fromJson(await link.getJson('/api/eq'));

  @override
  Future<void> chooseSound(String id) async {
    var now = await eq();
    if (now.preset == id) return;
    try {
      await link.postJson('/api/eq', {'rev': now.rev, 'preset': id});
    } on PanelError catch (e) {
      // the panel changed the document meanwhile: the choice is made on its version
      if (e.status != 409) rethrow;
      now = await eq();
      await link.postJson('/api/eq', {'rev': now.rev, 'preset': id});
    }
  }

  @override
  Future<int> setEqBands(int rev, List<EqBand> bands) async {
    try {
      final reply = await link.postJson('/api/eq', {
        'rev': rev,
        'bands': [for (final b in bands) b.toJson()],
      });
      return reply is Map && reply['rev'] is int ? reply['rev'] as int : rev;
    } on PanelError catch (e) {
      if (e.status == 409) throw const EqChanged();
      rethrow;
    }
  }

  @override
  Future<void> keepSound() => link.postJson('/api/eq', {'keep': true});

  @override
  Future<void> setBass(int db) =>
      link.write({Keys.audioBassDb.name: db.clamp(-6, 6)});

  @override
  Future<void> setTreble(int db) =>
      link.write({Keys.audioTrebleDb.name: db.clamp(-6, 6)});

  /// On puts back the strength it had, which the panel keeps (audio.loud_back), so the glass, the
  /// web and the app put back the same one.
  @override
  Future<void> setLoudness(bool on) {
    final back = Keys.audioLoudBack.of(link.state) ?? 0;
    return link.write({
      Keys.audioLoudness.name: on ? (back > 0 ? back : 70) : 0,
    });
  }

  @override
  Future<void> setEqOn(bool on) => link.write({Keys.audioEqEnabled.name: on});

  @override
  Future<void> setLeveler(bool on) => link.write({Keys.audioLeveler.name: on});

  @override
  Future<void> setLevelerSchedule({bool? on, int? from, int? to}) =>
      link.write({
        Keys.audioLevSched.name: ?on,
        Keys.audioLevFrom.name: ?from?.clamp(0, 1435),
        Keys.audioLevTo.name: ?to?.clamp(0, 1435),
      });

  @override
  Future<void> setVolMax(int percent) =>
      link.write({Keys.audioVolMax.name: percent.clamp(40, 100)});

  @override
  Future<void> setVolStart(int percent) =>
      link.write({Keys.audioVolStart.name: percent.clamp(0, 100)});

  @override
  Future<void> setAudio(AudioSetting setting, int value) =>
      link.write({setting.key.name: value.clamp(setting.min, setting.max)});

  @override
  Future<void> setSpeakers(SpeakerWrite write) => link.write(write.settings);

  @override
  Future<void> setPortMeter(bool on) =>
      link.write({Keys.audioPortMeas.name: on});

  @override
  Future<void> setPortMeterChannel(int channel) =>
      link.write({Keys.audioPortMeasCh.name: channel == 2 ? 2 : 1});

  @override
  Future<({String status, double hz})> portMeterReading() async {
    final raw = await link.getJson('/api/state');
    final s = raw is Map
        ? raw.cast<String, Object?>()
        : const <String, Object?>{};
    return (
      status: Keys.audioPortMeasStatus.of(s) ?? '',
      hz: Keys.audioPortMeasHz.of(s) ?? 0,
    );
  }

  @override
  Future<void> playTone({
    required int hz,
    ToneMode mode = ToneMode.chain,
    bool portOff = false,
    int? volCap,
  }) => link.write({
    if (portOff) Keys.audioCalPortOff.name: true,
    Keys.audioCalVolCap.name: ?volCap,
    Keys.audioToneMode.name: mode.value,
    Keys.audioToneHz.name: hz.clamp(20, 20000),
    Keys.audioSource.name: SourceId.tone.value,
  });

  @override
  Future<void> stopTone({SourceId? then, SpeakerWrite? write}) => link.write({
    Keys.audioSource.name: ?then?.value,
    Keys.audioToneMode.name: ToneMode.chain.value,
    ...?write?.settings,
  });

  @override
  Future<StationList> stations() async =>
      stationsOf(await link.getJson('/api/stations'));

  @override
  Future<void> listen(int index) {
    final s = link.state;
    if (index != (Keys.radioStation.of(s) ?? -1)) {
      return link.write({Keys.radioStation.name: index});
    }
    if (_current.now.playing) return Future.value();
    return link.write({Keys.radioCmd.name: 1});
  }

  /// Through the catalog's route, as the web does: radio.web_* names the station as the panel says
  /// it plays, radio.web_act 2…7 the button; a catalog station also goes into the list.
  @override
  Future<void> storePreset(int slot) {
    final s = link.state;
    return link.write({
      Keys.radioWebName.name: fitName(Keys.radioName.of(s) ?? ''),
      Keys.radioWebUrl.name: Keys.radioUrl.of(s) ?? '',
      Keys.radioWebUuid.name: Keys.radioUuid.of(s) ?? '',
      Keys.radioWebAct.name: slot + 2,
      if ((Keys.radioStation.of(s) ?? -1) < 0) Keys.radioFavAdd.name: true,
    });
  }

  @override
  Future<void> keepStation() => link.write({Keys.radioFavAdd.name: true});

  /// The panel takes the list on its next tick (202) and moves `radio.list_rev`.
  @override
  Future<StationsSave> saveStations(StationList edited) async {
    try {
      await link.postJson(
        '/api/stations',
        edited.toJson(),
        ok: const [200, 202],
      );
      return StationsSave.saved;
    } on PanelError catch (e) {
      if (e.status == 409) return StationsSave.changed;
      rethrow;
    }
  }

  /// The action last: the panel acts once the other three are written.
  @override
  Future<void> catalogStation({
    required String name,
    required String url,
    String uuid = '',
    required int act,
  }) => link.write({
    Keys.radioWebName.name: fitName(name),
    Keys.radioWebUrl.name: url,
    Keys.radioWebUuid.name: uuid,
    Keys.radioWebAct.name: act,
  });

  @override
  Future<List<Genre>> radioGenres() async =>
      genresOf(await link.getJson('/radio_genres.json'));

  @override
  Uri? web(String route) =>
      link.endpoint.http('/').replace(fragment: '/$route');

  /// The Player's cover: the panel's 280-pixel tile as a BMP (the firmware's UI.md, "Module HTTP
  /// routes"), asked again only when `ui.cover` names another picture — and then with the ETag of
  /// the one kept, which the panel answers 304 to when it has not changed.
  @override
  Future<Uint8List?> cover(String key) async {
    final kept = _cover;
    if (kept != null && kept.key == key) return kept.bytes;
    final got = await link.getBytes(
      '/api/cover',
      query: const {'px': '280'},
      etag: kept?.etag,
    );
    switch (got.status) {
      case 200:
        _cover = (key: key, bytes: got.bytes, etag: got.etag);
        return got.bytes;
      case 304 when kept != null:
        _cover = (key: key, bytes: kept.bytes, etag: kept.etag);
        return kept.bytes;
      default:
        _cover = null;
        return null;
    }
  }

  ({String key, Uint8List bytes, String? etag})? _cover;

  @override
  void suspend() => link.stop();

  @override
  void resume() => link.start();

  @override
  void dispose() {
    _sub.cancel();
    _changes.close();
    link.dispose();
  }
}

/// The models for one moment of a panel's state.
DeviceSnapshot snapshotOf(
  Map<String, Object?> s, {
  LinkStatus status = LinkStatus.ready,
  bool known = true,
}) {
  final f = face(s);
  return DeviceSnapshot(
    name: Keys.airplayName.of(s) ?? Keys.dlnaName.of(s) ?? '',
    scheme: Keys.uiTheme.of(s) ?? 0,
    now: nowOf(f, s),
    cards: cardsOf(f, s),
    volume: Keys.audioVolume.of(s) ?? 0,
    muted: Keys.audioMute.of(s) ?? false,
    status: status,
    known: known,
    backdrop: switch (Keys.uiCoverRgb.of(s)) {
      final rgb? when rgb > 0 => rgb,
      _ => null,
    },
    hostname: Keys.mdnsHostname.of(s) ?? '',
    cardIndex: Keys.playerIndex.of(s) ?? -1,
    cardCount: Keys.playerCount.of(s) ?? 0,
    sound: SoundState(
      bass: Keys.audioBassDb.of(s) ?? 0,
      treble: Keys.audioTrebleDb.of(s) ?? 0,
      loudness: (Keys.audioLoudness.of(s) ?? 0) > 0,
      eqOn: Keys.audioEqEnabled.of(s) ?? true,
      leveler: Keys.audioLeveler.of(s),
      eqRev: Keys.audioEqRev.of(s) ?? 0,
      volMax: Keys.audioVolMax.of(s),
      volStart: Keys.audioVolStart.of(s),
      levSchedule: Keys.audioLevSched.of(s),
      levFrom: Keys.audioLevFrom.of(s) ?? 22 * 60,
      levTo: Keys.audioLevTo.of(s) ?? 7 * 60,
      loudDb: Keys.audioLoudDb.of(s) ?? 0,
      hpHz: Keys.audioHpHz.of(s) ?? 40,
      // closed speakers have no port, whatever number is kept (the web's speakers.js port())
      portHz: speakersOf(s).port.hz,
      portLiftDb: Keys.audioPortLiftDb.of(s) ?? 3,
      loudnessLevel: Keys.audioLoudness.of(s) ?? 70,
      loudRef: Keys.audioLoudRef.of(s) ?? 100,
      width: Keys.audioWidth.of(s) ?? 100,
      monoBassHz: Keys.audioMonoBassHz.of(s) ?? 0,
      bassXoHz: Keys.audioBassXoHz.of(s) ?? 120,
    ),
    speakers: SpeakerState(
      setup: speakersOf(s),
      balanceDb10: Keys.audioBalanceDb10.of(s) ?? 0,
      measuring: Keys.audioPortMeas.of(s),
      meterChannel: Keys.audioPortMeasCh.of(s) ?? 1,
      meterStatus: Keys.audioPortMeasStatus.of(s) ?? '',
      meterHz: Keys.audioPortMeasHz.of(s) ?? 0,
    ),
    tone: ToneState(
      on: Keys.audioSource.of(s) == SourceId.tone.value,
      mode: ToneMode.of(Keys.audioToneMode.of(s)),
      hz: Keys.audioToneHz.of(s) ?? 1000,
      db10: Keys.audioToneDb10.of(s) ?? -260,
      channel: ToneChannel.of(Keys.audioToneCh.of(s)),
    ),
    radio: radioOf(s),
  );
}

/// The speakers as the panel keeps them.
Speakers speakersOf(Map<String, Object?> s) => Speakers(
  type: SpeakerType.of(Keys.audioSpkType.of(s)),
  portHz: Keys.audioPortHz.of(s) ?? 0,
  source: PortSource.of(Keys.audioPortSrc.of(s)),
);

StationState radioOf(Map<String, Object?> s) {
  final current = Keys.radioStation.of(s) ?? -1;
  return StationState(
    current: current,
    count: Keys.radioCount.of(s) ?? 0,
    listRev: Keys.radioListRev.of(s) ?? 0,
    storable:
        (Keys.radioUrl.of(s) ?? '').isNotEmpty &&
        (current >= 0 || (Keys.radioName.of(s) ?? '').isNotEmpty),
  );
}

/// `GET /api/stations`: a preset that names no station of the list is empty.
StationList stationsOf(Object? json) {
  final d = json is Map ? json : const {};
  final list = d['list'] is Map ? d['list'] as Map : const {};
  final stations = [
    for (final st
        in list['stations'] is List ? list['stations'] as List : const [])
      if (st is Map && st['name'] is String && st['url'] is String)
        Station(
          name: st['name'] as String,
          url: st['url'] as String,
          uuid: st['uuid'] is String ? st['uuid'] as String : '',
        ),
  ];
  final raw = list['presets'] is List ? list['presets'] as List : const [];
  return StationList(
    rev: d['rev'] is int ? d['rev'] as int : 0,
    stations: stations,
    presets: [
      for (var i = 0; i < StationList.presetCount; i++)
        switch (i < raw.length ? raw[i] : null) {
          final int p when p >= 0 && p < stations.length => p,
          _ => -1,
        },
    ],
  );
}

/// What the Player shows: the face, with the buttons the panel says the source takes.
NowPlaying nowOf(Face f, Map<String, Object?> s) {
  final caps = Keys.audioTransportCaps.of(s) ?? 0;
  final name = f.subtitleArgs?['name'];
  final technical = f.kind == 'usb' || f.kind == 'tone';
  final track = f.progress == 'track' && f.dur > 0;
  final cover = Keys.uiCover.of(s) ?? 0;
  return NowPlaying(
    kind: NowKind.values.byName(f.kind),
    title: f.title != null
        ? TextLabel(f.title!)
        : LineLabel(_lines[f.titleKey] ?? CatalogLine.off, name: name),
    subtitle: f.subtitle != null && f.subtitle!.isNotEmpty
        ? TextLabel(f.subtitle!, technical: technical)
        : f.subtitleKey != null
        ? LineLabel(_lines[f.subtitleKey] ?? CatalogLine.pick, name: name)
        : null,
    device: f.device,
    format: f.format,
    playing: f.playing,
    canToggle: Transport.takes(caps, Transport.toggle),
    canPrevious: Transport.takes(caps, Transport.previous),
    canNext: Transport.takes(caps, Transport.next),
    position: track ? _seconds(f.pos) : null,
    duration: track ? _seconds(f.dur) : null,
    coverKey: cover > 0 ? '$cover' : null,
    live: f.live,
    seekable: f.seekKey != null && f.live,
    repeat: f.repeat,
    shuffle: f.shuffle,
  );
}

/// The panel's genre table (radio_genres.json): `name` is Ukrainian, `name_<lang>` the others.
List<Genre> genresOf(Object? json) {
  final d = json is Map ? json : const {};
  return [
    for (final g in d['genres'] is List ? d['genres'] as List : const [])
      if (g is Map && g['tag'] is String && g['name'] is String)
        Genre(
          tag: g['tag'] as String,
          names: {
            'uk': g['name'] as String,
            for (final lang in const ['en', 'de', 'pl'])
              if (g['name_$lang'] is String) lang: g['name_$lang'] as String,
          },
        ),
  ];
}

/// `GET /api/library?from=&n=`: one page of the card's index.
LibraryPage libraryOf(Object? json) {
  final d = json is Map ? json : const {};
  int number(String k, int or) => d[k] is int ? d[k] as int : or;
  return LibraryPage(
    gen: number('gen', 0),
    busy: d['busy'] == true,
    count: number('count', 0),
    cursor: number('cursor', -1),
    root: d['root'] is String ? d['root'] as String : '',
    from: number('from', 0),
    rows: [
      for (final r in d['rows'] is List ? d['rows'] as List : const [])
        if (r is String) r,
    ],
  );
}

/// `GET /api/dlna/browser`: the browser's snapshot.
DlnaView dlnaViewOf(Object? json) {
  final d = json is Map ? json : const {};
  String text(Map m, String k) => m[k] is String ? m[k] as String : '';
  return DlnaView(
    revision: d['revision'] is int ? d['revision'] as int : 0,
    busy: d['busy'] == true,
    servers: d['servers'] == true,
    canBack: d['can_back'] == true,
    count: d['count'] is int ? d['count'] as int : 0,
    next: d['next'] == true,
    previous: d['previous'] == true,
    title: text(d, 'title'),
    status: text(d, 'status'),
    rows: [
      for (final r in d['rows'] is List ? d['rows'] as List : const [])
        if (r is Map)
          DlnaRow(
            title: text(r, 'title'),
            artist: text(r, 'artist'),
            folder: r['folder'] == true,
            playable: r['playable'] == true,
          ),
    ],
  );
}

Duration _seconds(num s) => Duration(milliseconds: (s * 1000).round());

/// The catalog keys now.js names, as the app's lines.
const _lines = {
  'now.no_device': CatalogLine.noDevice,
  'now.dlna_track': CatalogLine.dlnaTrack,
  'now.connecting': CatalogLine.connecting,
  'now.buffering': CatalogLine.buffering,
  'now.reconnecting': CatalogLine.reconnecting,
  'now.stopped': CatalogLine.stopped,
  'now.airplay_waiting': CatalogLine.airplayWaiting,
  'now.airplay_pick': CatalogLine.airplayPick,
  'now.usb': CatalogLine.usb,
  'now.usb_waiting': CatalogLine.usbWaiting,
  'now.usb_pick': CatalogLine.usbPick,
  'now.tone': CatalogLine.tone,
  'now.aux': CatalogLine.aux,
  'now.off': CatalogLine.off,
  'now.pick': CatalogLine.pick,
  'src.radio': CatalogLine.radio,
};

/// The Source page's cards: those whose bit is in `audio.sources`, each saying what it would
/// give now — a port of describe() in the firmware's webui/src/pages/SourcePage.svelte
/// (screen_src.cpp on the glass).
List<SourceCardState> cardsOf(Face f, Map<String, Object?> s) {
  final sources = Keys.audioSources.of(s) ?? 0;
  bool active(SourceCard c) =>
      f.kind == c.name || (c == SourceCard.servers && f.kind == 'dlna');
  Label? playing(SourceCard c) =>
      active(c) && f.title != null ? TextLabel(f.title!) : null;
  Label status(SourceCard c) {
    switch (c) {
      case SourceCard.bt:
        return playing(c) ??
            LineLabel(
              (Keys.btPeer.of(s) ?? '').isNotEmpty
                  ? CatalogLine.phoneOn
                  : CatalogLine.phoneOff,
            );
      case SourceCard.servers:
        return playing(c) ?? const LineLabel(CatalogLine.servers);
      case SourceCard.card:
        final n = Keys.playerCount.of(s) ?? 0;
        return playing(c) ??
            (n > 0
                ? LineLabel(CatalogLine.tracks, count: n)
                : const LineLabel(CatalogLine.cardNone));
      case SourceCard.radio:
        final name = Keys.radioName.of(s) ?? '';
        if (name.isNotEmpty) return TextLabel(name);
        final n = Keys.radioCount.of(s) ?? 0;
        return n > 0
            ? LineLabel(CatalogLine.stations, count: n)
            : const LineLabel(CatalogLine.radioNone);
      case SourceCard.airplay:
        final on = const [
          'connected',
          'playing',
          'paused',
        ].contains(Keys.airplayState.of(s));
        return playing(c) ??
            LineLabel(on ? CatalogLine.phoneOn : CatalogLine.airplayWait);
      case SourceCard.usb:
        // what the computer sends once it sends; otherwise whether there is one
        if (active(c) && (f.subtitle ?? '').isNotEmpty) {
          return TextLabel(f.subtitle!, technical: true);
        }
        final on = const [
          'ready',
          'playing',
        ].contains(Keys.usbAudioState.of(s));
        return LineLabel(on ? CatalogLine.usbOn : CatalogLine.usbWait);
    }
  }

  return [
    for (final c in SourceCard.values)
      if (sources & (1 << c.source.value) != 0)
        SourceCardState(c, active: active(c), status: status(c)),
  ];
}
