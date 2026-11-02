/// What the app knows about a panel, whichever DeviceApi it came from: the demo, or the panel's
/// HTTP API and WebSocket. Widgets read these and never a state key.
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

/// Which face the Player shows: a source's, or DLNA's for a track a control point pushed, which
/// rides the radio's source (the web's now.js `kind`).
enum NowKind {
  off(SourceId.off),
  tone(SourceId.tone),
  aux(SourceId.aux),
  bt(SourceId.bt),
  card(SourceId.card),
  radio(SourceId.radio),
  dlna(SourceId.radio),
  airplay(SourceId.airplay),
  usb(SourceId.usb);

  const NowKind(this.source);

  final SourceId source;

  /// The Player names where the sound comes from, except for what is not played from anywhere.
  bool get hasOrigin => this != off && this != tone && this != aux;
}

/// The Source page's cards, in the panel's order (screen_src.cpp CARDS). The media servers ride
/// the radio's source; their card opens the browser.
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
  dlnaTrack,
  connecting,
  buffering,
  reconnecting,
  stopped,
  airplayWaiting,
  airplayPick,
  usb,
  usbWaiting,
  usbPick,
  tone,
  aux,
  off,
  pick,
  radio,
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
  const TextLabel(this.text, {this.technical = false});

  final String text;

  /// A rate or a frequency ("48.0 kHz 24 bit"), which a page writes in its language's units.
  final bool technical;
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
    required this.kind,
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
    this.live = true,
    this.seekable = false,
    this.repeat,
    this.shuffle,
  });

  final NowKind kind;
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

  /// Someone is there to take the transport: Bluetooth needs a phone, AirPlay a remote.
  final bool live;

  /// The position can be moved — a card's track, a stream that seeks.
  final bool seekable;

  /// The card's queue: repeat 0 off, 1 one track, 2 all; null where the source has no queue.
  final int? repeat;
  final bool? shuffle;

  SourceId get source => kind.source;
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

/// How the app hears the panel.
enum LinkStatus {
  /// The state is the panel's, as of now.
  ready,

  /// Connecting, or connecting again after the panel went quiet: the state shown is the last one.
  connecting,

  /// The panel has its three WebSocket clients already (close code 1013); trying again.
  busy,
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
    this.status = LinkStatus.ready,
    this.known = true,
    this.backdrop,
    this.sound = const SoundState(),
    this.radio = const StationState(),
    this.hostname = '',
    this.cardIndex = -1,
    this.cardCount = 0,
  });

  /// The panel's device name — what AirPlay and Bluetooth list it by.
  final String name;

  /// The panel's mDNS host name ("modesp-2c4c"): what the app knows it by, however it was added;
  /// empty until it says so, and for the demo.
  final String hostname;

  /// The card's queue: the track it is on, by its place in the library (−1 for none), and how
  /// many tracks the card has — a new count is a new card.
  final int cardIndex;
  final int cardCount;

  /// `ui.theme`: the panel's colour scheme, which the app wears too.
  final int scheme;
  final NowPlaying now;
  final List<SourceCardState> cards;

  /// 0…100 %.
  final int volume;
  final bool muted;
  final LinkStatus status;

  /// False until the panel has sent its state once: nothing above is the panel's yet.
  final bool known;

  /// The Player's background, 0xRRGGBB: the panel's tint of the cover (`ui.cover_rgb`, a dark,
  /// muted shade of it), or null without one.
  final int? backdrop;
  final SoundState sound;
  final StationState radio;
}

enum TransportAction { toggle, previous, next }

/// The daily sound: what the «Звук» sheet and the moon show.
class SoundState {
  const SoundState({
    this.bass = 0,
    this.treble = 0,
    this.loudness = false,
    this.eqOn = true,
    this.leveler,
    this.eqRev = 0,
  });

  /// −6…+6 dB.
  final int bass;
  final int treble;
  final bool loudness;
  final bool eqOn;

  /// The night leveler, or null where the panel has none.
  final bool? leveler;

  /// Moves whenever the EQ document changes, wherever it was changed.
  final int eqRev;
}

/// The sounds a panel offers and the one it plays (the EQ document's, `GET /api/eq`).
class SoundPresets {
  const SoundPresets({
    required this.rev,
    required this.preset,
    required this.presets,
  });

  final int rev;
  final String preset;
  final List<String> presets;
}

/// The radio as its card needs it.
class StationState {
  const StationState({
    this.current = -1,
    this.count = 0,
    this.listRev = 0,
    this.storable = false,
  });

  /// The station tuned, by its place in the list; −1 for one from the catalog.
  final int current;
  final int count;

  /// Moves whenever the list or its presets change.
  final int listRev;

  /// What plays can go on a preset: a station of the list, or a named one from the catalog.
  final bool storable;

  /// A catalog station not in the list, which can be kept in it.
  bool get keepable => current < 0 && storable;
}

class Station {
  const Station({required this.name, required this.url, this.uuid = ''});

  final String name;
  final String url;
  final String uuid;
}

/// The station list and its six presets (indices into the list, −1 empty).
class StationList {
  const StationList({
    required this.rev,
    required this.stations,
    required this.presets,
  });

  final int rev;
  final List<Station> stations;
  final List<int> presets;

  static const presetCount = 6;
}

/// One page of the card's index (`GET /api/library`).
class LibraryPage {
  const LibraryPage({
    required this.gen,
    required this.busy,
    required this.count,
    required this.cursor,
    required this.root,
    required this.from,
    required this.rows,
  });

  /// Moves whenever the panel builds the index again.
  final int gen;

  /// The panel is still reading the card.
  final bool busy;
  final int count;

  /// The track the queue is on, −1 for none.
  final int cursor;

  /// The folder the rows are under.
  final String root;
  final int from;

  /// Paths under [root].
  final List<String> rows;
}

/// The DLNA browser as it is now (`GET /api/dlna/browser`) — one browser for the glass, the web and
/// the app.
class DlnaView {
  const DlnaView({
    required this.revision,
    required this.busy,
    required this.servers,
    required this.canBack,
    required this.count,
    required this.next,
    required this.previous,
    required this.title,
    required this.status,
    required this.rows,
  });

  /// Every command names the revision it was chosen from.
  final int revision;

  /// Something is being fetched.
  final bool busy;

  /// The rows are servers, not a folder's entries.
  final bool servers;
  final bool canBack;
  final int count;

  /// More pages either way.
  final bool next;
  final bool previous;

  /// The folder's name, or the catalog message of the servers' list (`@dlna.servers`).
  final String title;

  /// A catalog message (`@dlna.*`, arguments after U+001F).
  final String status;
  final List<DlnaRow> rows;
}

class DlnaRow {
  const DlnaRow({
    required this.title,
    this.artist = '',
    this.folder = false,
    this.playable = false,
  });

  final String title;
  final String artist;
  final bool folder;
  final bool playable;
}

/// What the panel said to an edited station list.
enum StationsSave {
  /// It took the list; `radio.list_rev` moves.
  saved,

  /// The list had moved on the panel meanwhile (409): read it again, edit again.
  changed,
}

/// A genre of the catalogue: its Radio Browser tag and its name in the four languages — the
/// table the panel serves (data/www/radio_genres.json) and the glass reads too.
class Genre {
  const Genre({required this.tag, required this.names});

  final String tag;

  /// Language code → name; Ukrainian is the table's own `name`.
  final Map<String, String> names;

  String nameIn(String language) => names[language] ?? names['uk'] ?? tag;
}
