/// What the app knows about a panel, whichever [DeviceApi] it came from: the demo now, the
/// panel's HTTP API and WebSocket later. Widgets read these and never a state key.
library;

/// The values of `audio.source` (the firmware's CONCEPT.md, "SharedState contract: sources").
enum SourceId {
  off(0),
  tone(1),
  aux(2),
  bt(3),
  card(4),
  radio(5),
  airplay(6),
  usb(7);

  const SourceId(this.value);

  final int value;
}

/// The Source page's cards, in the panel's order (screen_src.cpp CARDS). The media servers ride
/// the radio's source; the app opens them in the panel's web interface.
enum SourceCard {
  bt(SourceId.bt),
  airplay(SourceId.airplay),
  radio(SourceId.radio),
  card(SourceId.card),
  servers(SourceId.radio),
  usb(SourceId.usb);

  const SourceCard(this.source);

  final SourceId source;
}

/// A line the app's catalog words, rather than the panel: a state, a hint, a count.
enum CatalogLine {
  noDevice,
  airplayWaiting,
  airplayPick,
  usbWaiting,
  usbPick,
  off,
  pick,
  connecting,
  phoneOn,
  phoneOff,
  servers,
  tracks,
  cardNone,
  stations,
  radioNone,
  airplayWait,
  usbOn,
  usbWait,
}

/// Text on a page: either the panel's own (a title, a station name) or a catalog line.
sealed class Label {
  const Label();
}

final class TextLabel extends Label {
  const TextLabel(this.text);

  final String text;
}

final class LineLabel extends Label {
  const LineLabel(this.line, {this.name, this.count});

  final CatalogLine line;

  /// The panel's name, for the lines that tell what to pick on a phone or a computer.
  final String? name;

  /// How many, for the lines with a plural.
  final int? count;
}

/// What the Player shows for the source that plays, and which buttons that source has.
class NowPlaying {
  const NowPlaying({
    required this.source,
    required this.title,
    this.subtitle,
    this.device = '',
    this.format = '',
    this.playing = false,
    this.canToggle = false,
    this.canPrevious = false,
    this.canNext = false,
    this.position,
    this.duration,
    this.coverKey,
  });

  final SourceId source;
  final Label title;
  final Label? subtitle;

  /// The phone or computer it plays from, or ''.
  final String device;

  /// The codec badge as the panel writes it ("LHDC V5 96.0 kHz"), or ''.
  final String format;
  final bool playing;
  final bool canToggle;
  final bool canPrevious;
  final bool canNext;

  /// Where in the track; null where a source has no track (a station, a waiting input).
  final Duration? position;
  final Duration? duration;

  /// What the cover is of; null when there is none.
  final String? coverKey;
}

/// One card on the Source page.
class SourceCardState {
  const SourceCardState(
    this.card, {
    required this.active,
    required this.status,
  });

  final SourceCard card;
  final bool active;
  final Label status;
}

/// Everything a page needs about the panel at one moment.
class DeviceSnapshot {
  const DeviceSnapshot({
    required this.name,
    required this.scheme,
    required this.now,
    required this.cards,
    required this.volume,
    required this.muted,
  });

  /// The panel's device name — what AirPlay and Bluetooth list it by.
  final String name;

  /// `ui.theme`: the panel's colour scheme, which the app wears too.
  final int scheme;
  final NowPlaying now;
  final List<SourceCardState> cards;

  /// 0…100 %.
  final int volume;
  final bool muted;
}

enum TransportAction { toggle, previous, next }
