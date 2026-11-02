import 'dart:async';

import '../device_api.dart';
import '../face.dart';
import '../keys.dart';
import '../models.dart';
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
  Future<void> selectSource(SourceId source) => link.write({
    Keys.audioSource.name: source.value,
    // the radio plays as it is chosen, as the glass and the web do (screen_src.cpp)
    if (source == SourceId.radio) Keys.radioCmd.name: 1,
  });

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
