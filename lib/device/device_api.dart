import 'dart:typed_data';

import 'eq.dart';
import 'keys.dart';
import 'maintenance.dart';
import 'models.dart';
import 'speakers.dart';
import 'streamer.dart';

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

  /// The EQ document: the sounds offered, the one that plays and its bands.
  Future<EqDoc> eq();

  /// Plays sound [id]. A panel that changed the EQ meanwhile (409) is read again and the choice
  /// made on its version — a choice is not an edit to merge.
  Future<void> chooseSound(String id);

  /// Section 0's bands, set by hand on the document of revision [rev] — the sound becomes
  /// «Власний»: the panel's revision after it. Throws [EqChanged] when the document moved
  /// meanwhile (409): it is read again rather than written over.
  Future<int> setEqBands(int rev, List<EqBand> bands);

  /// A sound page closed: the panel writes the EQ at once rather than a minute after the last edit.
  Future<void> keepSound();

  Future<void> setBass(int db);

  Future<void> setTreble(int db);

  Future<void> setLoudness(bool on);

  Future<void> setEqOn(bool on);

  Future<void> setLeveler(bool on);

  /// The leveler by the clock: the schedule on or off, its window's ends in minutes of the day
  /// (a step of 5).
  Future<void> setLevelerSchedule({bool? on, int? from, int? to});

  /// «Максимум», 40…100 % in steps of 5.
  Future<void> setVolMax(int percent);

  /// The volume after power-on is no higher than this, 0…100 %; 0 leaves it as it was.
  Future<void> setVolStart(int percent);

  /// A sound setting a slider moves, held to the panel's range.
  Future<void> setAudio(AudioSetting setting, int value);

  /// What the speakers' wizard or the port page found: the type, the port and where it came from.
  Future<void> setSpeakers(SpeakerWrite write);

  /// The port meter on or off (~45 s; the panel's microphone at the speaker [setPortMeterChannel]
  /// names).
  Future<void> setPortMeter(bool on);

  /// The speaker the port meter listens at: 1 left, 2 right.
  Future<void> setPortMeterChannel(int channel);

  /// The port meter's last word and what it found, which the panel writes without WebSocket
  /// deltas: read from its whole state, while a page shows them.
  Future<({String status, double hz})> portMeterReading();

  /// The test tone at [hz], through the DSP and the volume unless [mode] says otherwise; [portOff]
  /// and [volCap] go with it and last only while it plays. Its keys go in one body, the source
  /// last, so the panel never starts it with what a step before asked.
  Future<void> playTone({
    required int hz,
    ToneMode mode = ToneMode.chain,
    bool portOff = false,
    int? volCap,
  });

  /// The tone off and its mode back through the DSP: the source [then] first (null leaves it as
  /// it is), and [write] in the same body — what a search by hand found.
  Future<void> stopTone({SourceId? then, SpeakerWrite? write});

  /// A setting of the screen's page or the language's, held to the streamer's range.
  Future<void> setPanel(PanelSetting setting, int value);

  /// AirPlay, DLNA, the radio's covers: on or off.
  Future<void> setSwitch(PanelSwitch service, bool on);

  /// 0 AirPlay 2, 1 AirPlay 1 for Windows.
  Future<void> setAirplayMode(int mode);

  /// The networks the streamer hears, strongest first; null when it could not look.
  Future<List<WifiNetwork>?> wifiScan();

  /// Joins [ssid] the way the glass does: the stored network is kept until the new one gives an
  /// address, and comes back if it does not; the outcome comes over the WebSocket (wifi.try).
  /// A join while another is on its way is refused, 409 `busy`.
  Future<void> wifiJoin(String ssid, String password);

  /// Forgets the network: the streamer goes to its own access point.
  Future<void> wifiForget();

  /// The access point the streamer falls back to.
  Future<WifiAp> wifiAp();

  /// The access point's name, password ('' for an open one) and channel, from the next start.
  Future<void> setWifiAp(String ssid, String password, int channel);

  Future<PanelTime> panelTime();

  /// The clock from the internet or by hand ([unix], seconds), and its time zone.
  Future<void> setPanelTime({
    required bool ntp,
    required String timezone,
    int? unix,
  });

  /// The Bluetooth module's settings.
  Future<BtInfo> bt();

  /// A change of the Bluetooth module's settings; a refusal is a [PanelError] (409, its code).
  Future<void> btSet({
    bool? radio,
    bool? discoverable,
    bool? autoReconnect,
    int? codecs,
    String? name,
  });

  /// Forgets a phone by its address, or every one ("all").
  Future<void> btForget(String addr);

  /// Lets the connected phone go.
  Future<void> btDisconnect();

  /// The answer to pairing request [seq]; one answered first elsewhere is 409 `answered`.
  Future<void> btPair({required bool accept, required int seq});

  /// Saves the settings, stops the modules, restarts.
  Future<void> restart();

  /// The streamer's login: on or off, and its name (without a login itself).
  Future<AuthInfo> auth();

  /// A change of the login: on or off, the name, or the password — which needs the one it has
  /// (403 `wrong_password`).
  Future<void> setAuth({
    bool? enabled,
    String? username,
    String? currentPassword,
    String? newPassword,
  });

  /// What runs now (without a login).
  Future<OtaInfo> otaInfo();

  /// A firmware image to the other slot; the streamer restarts into it. [progress] 0…1 as it goes
  /// out. An image of another board is refused, 400 `board_mismatch` with both names.
  Future<void> otaUpload(Uint8List image, {void Function(double)? progress});

  /// The person's own files — the station list, the EQ and «Власний», the remote devices, the
  /// track to resume — as one document.
  Future<Map<String, Object?>> userFiles();

  /// Those files back: staged, they go in at the next start; how many were.
  Future<int> restoreUserFiles(Map<String, Object?> doc);

  /// Every persisted setting.
  Future<Map<String, Object?>> settingsBackup();

  /// The settings back, every key at once; the streamer restarts to apply them.
  Future<void> restoreSettings(Map<String, Object?> doc);

  Future<StationList> stations();

  /// The glass's listen(): a station not tuned is a tune, the one tuned a play if it is off.
  Future<void> listen(int index);

  /// What plays into preset [slot] (0…5).
  Future<void> storePreset(int slot);

  /// The catalog station that plays, into the list.
  Future<void> keepStation();

  /// The edited list, sent whole with the generation it was made from ([StationList.rev]).
  /// Throws what the panel refused for any other reason.
  Future<StationsSave> saveStations(StationList edited);

  /// A station of the catalogue to the panel: [act] 0 plays it, 1 keeps it in the list, 2…7 keeps
  /// it on preset 1…6 (`radio.web_act`).
  Future<void> catalogStation({
    required String name,
    required String url,
    String uuid = '',
    required int act,
  });

  /// The catalogue's genres, as the panel lists them.
  Future<List<Genre>> radioGenres();

  /// A page of the card's index, at most [count] rows from [from].
  Future<LibraryPage> library({int from = 0, int count = 200});

  /// Plays the card's track at [path] — the root and the row (`trackPath`).
  Future<void> playTrack(String path);

  /// The DLNA browser as it is now.
  Future<DlnaView> dlnaView();

  /// A browser command, packed with its row and revision (`browseCode`).
  Future<void> dlnaCommand(int code);

  /// The picture of [NowPlaying.coverKey]; null when there is none to show.
  Future<Uint8List?> cover(String key);

  /// The app went to the background: let go of the panel (one of its three WebSocket slots).
  void suspend();

  /// The app is back: hear the panel again, starting from its whole state.
  void resume();

  void dispose();
}
