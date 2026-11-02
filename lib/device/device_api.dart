import 'dart:typed_data';

import 'models.dart';

/// A panel as the app sees it: `DemoDeviceApi`, or `PanelDeviceApi` for a real one. The app sends
/// a command and shows what the panel then reports — it never assumes a command took effect, and
/// nothing is queued while the panel is away.
abstract interface class DeviceApi {
  /// The panel now.
  DeviceSnapshot get current;

  /// Every later change.
  Stream<DeviceSnapshot> get changes;

  Future<void> setVolume(int percent);

  Future<void> setMuted(bool muted);

  Future<void> transport(TransportAction action);

  /// Moves the track to [seconds], where the source can seek ([NowPlaying.seekable]).
  Future<void> seek(int seconds);

  /// The card's queue: repeat 0 off, 1 one track, 2 all.
  Future<void> setRepeat(int mode);

  Future<void> setShuffle(bool on);

  Future<void> selectSource(SourceId source);

  /// The sounds the panel offers and the one it plays.
  Future<SoundPresets> soundPresets();

  /// Plays sound [id]. A panel that changed the EQ meanwhile (409) is read again and the choice
  /// made on its version — a choice is not an edit to merge.
  Future<void> chooseSound(String id);

  /// The sheet closed: the panel writes the chosen sound at once rather than a minute later.
  Future<void> keepSound();

  Future<void> setBass(int db);

  Future<void> setTreble(int db);

  Future<void> setLoudness(bool on);

  Future<void> setEqOn(bool on);

  Future<void> setLeveler(bool on);

  Future<StationList> stations();

  /// The glass's listen(): a station not tuned is a tune, the one tuned a play if it is off.
  Future<void> listen(int index);

  /// What plays into preset [slot] (0…5).
  Future<void> storePreset(int slot);

  /// The catalog station that plays, into the list.
  Future<void> keepStation();

  /// A page of the card's index, at most [count] rows from [from].
  Future<LibraryPage> library({int from = 0, int count = 200});

  /// Plays the card's track at [path] — the root and the row (`trackPath`).
  Future<void> playTrack(String path);

  /// The DLNA browser as it is now.
  Future<DlnaView> dlnaView();

  /// A browser command, packed with its row and revision (`browseCode`).
  Future<void> dlnaCommand(int code);

  /// A page of the panel's web interface ("system/sound/eq"), or null where there is none.
  Uri? web(String route);

  /// The picture of [NowPlaying.coverKey]; null when there is none to show.
  Future<Uint8List?> cover(String key);

  /// The app went to the background: let go of the panel (one of its three WebSocket slots).
  void suspend();

  /// The app is back: hear the panel again, starting from its whole state.
  void resume();

  void dispose();
}
