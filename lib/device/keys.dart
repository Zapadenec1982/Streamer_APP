/// The panel's state keys the app reads and writes. Their types and access are the firmware's
/// (protocol/state_meta.json, from the modules' manifests); test/keys_test.dart holds these to it.
library;

class StateKey<T extends Object> {
  const StateKey(this.name, {this.writable = false, this.framework = false});

  final String name;
  final bool writable;

  /// A key of the ModESP framework (Wi-Fi, system), which the modules' manifests do not list.
  final bool framework;

  /// The type state_meta gives the key.
  String get metaType => T == int
      ? 'int'
      : T == bool
      ? 'bool'
      : T == double
      ? 'float'
      : 'string';

  /// The key's value in a state, or null when the panel has not sent it or sent another type.
  T? of(Map<String, Object?> state) {
    final v = state[name];
    if (T == double && v is num) return v.toDouble() as T;
    return v is T ? v : null;
  }
}

abstract final class Keys {
  static const audioSource = StateKey<int>('audio.source', writable: true);
  static const audioSources = StateKey<int>('audio.sources');
  static const audioVolume = StateKey<int>('audio.volume', writable: true);
  static const audioMute = StateKey<bool>('audio.mute', writable: true);
  static const audioTransport = StateKey<int>(
    'audio.transport',
    writable: true,
  );
  static const audioTransportCaps = StateKey<int>('audio.transport_caps');
  static const radioCmd = StateKey<int>('radio.cmd', writable: true);
  static const uiTheme = StateKey<int>('ui.theme', writable: true);
  static const uiCover = StateKey<int>('ui.cover');
  static const uiCoverRgb = StateKey<int>('ui.cover_rgb');
  static const airplayName = StateKey<String>('airplay.name');
  static const airplayState = StateKey<String>('airplay.state');
  static const dlnaName = StateKey<String>('dlna.name');
  static const btPeer = StateKey<String>('bt.peer');
  static const playerCount = StateKey<int>('player.count');
  static const radioCount = StateKey<int>('radio.count');
  static const radioName = StateKey<String>('radio.name');
  static const usbAudioState = StateKey<String>('usb_audio.state');
  static const audioBassDb = StateKey<int>('audio.bass_db', writable: true);
  static const audioTrebleDb = StateKey<int>('audio.treble_db', writable: true);
  static const audioLoudness = StateKey<int>('audio.loudness', writable: true);
  static const audioLoudBack = StateKey<int>('audio.loud_back');
  static const audioEqEnabled = StateKey<bool>(
    'audio.eq_enabled',
    writable: true,
  );
  static const audioEqRev = StateKey<int>('audio.eq_rev');
  static const audioLeveler = StateKey<bool>('audio.leveler', writable: true);
  static const audioLevSched = StateKey<bool>(
    'audio.lev_sched',
    writable: true,
  );
  static const audioLevFrom = StateKey<int>('audio.lev_from', writable: true);
  static const audioLevTo = StateKey<int>('audio.lev_to', writable: true);
  static const audioVolMax = StateKey<int>('audio.vol_max', writable: true);
  static const audioVolStart = StateKey<int>('audio.vol_start', writable: true);
  static const audioLoudDb = StateKey<double>('audio.loud_db');
  static const audioHpHz = StateKey<int>('audio.hp_hz', writable: true);
  static const audioSpkType = StateKey<int>('audio.spk_type', writable: true);
  static const audioPortHz = StateKey<int>('audio.port_hz', writable: true);
  static const audioPortLiftDb = StateKey<int>(
    'audio.port_lift_db',
    writable: true,
  );
  static const radioStation = StateKey<int>('radio.station', writable: true);
  static const radioListRev = StateKey<int>('radio.list_rev');
  static const radioUrl = StateKey<String>('radio.url');
  static const radioUuid = StateKey<String>('radio.uuid');
  static const radioWebName = StateKey<String>(
    'radio.web_name',
    writable: true,
  );
  static const radioWebUrl = StateKey<String>('radio.web_url', writable: true);
  static const radioWebUuid = StateKey<String>(
    'radio.web_uuid',
    writable: true,
  );
  static const radioWebAct = StateKey<int>('radio.web_act', writable: true);
  static const radioFavAdd = StateKey<bool>('radio.fav_add', writable: true);
  static const playerTrack = StateKey<String>('player.track', writable: true);
  static const playerCmd = StateKey<int>('player.cmd', writable: true);
  static const playerIndex = StateKey<int>('player.index');
  static const playerRepeat = StateKey<int>('player.repeat', writable: true);
  static const playerShuffle = StateKey<bool>('player.shuffle', writable: true);
  static const playerSeekS = StateKey<int>('player.seek_s', writable: true);
  static const radioSeekS = StateKey<int>('radio.seek_s', writable: true);
  static const dlnaBrowseCmd = StateKey<int>('dlna.browse_cmd', writable: true);
  static const mdnsHostname = StateKey<String>(
    'system.mdns_hostname',
    framework: true,
  );

  static const all = <StateKey<Object>>[
    audioSource,
    audioSources,
    audioVolume,
    audioMute,
    audioTransport,
    audioTransportCaps,
    radioCmd,
    uiTheme,
    uiCover,
    uiCoverRgb,
    airplayName,
    airplayState,
    dlnaName,
    btPeer,
    playerCount,
    radioCount,
    radioName,
    usbAudioState,
    audioBassDb,
    audioTrebleDb,
    audioLoudness,
    audioLoudBack,
    audioEqEnabled,
    audioEqRev,
    audioLeveler,
    audioLevSched,
    audioLevFrom,
    audioLevTo,
    audioVolMax,
    audioVolStart,
    audioLoudDb,
    audioHpHz,
    audioSpkType,
    audioPortHz,
    audioPortLiftDb,
    radioStation,
    radioListRev,
    radioUrl,
    radioUuid,
    radioWebName,
    radioWebUrl,
    radioWebUuid,
    radioWebAct,
    radioFavAdd,
    playerTrack,
    playerCmd,
    playerIndex,
    playerRepeat,
    playerShuffle,
    playerSeekS,
    radioSeekS,
    dlnaBrowseCmd,
    mdnsHostname,
  ];
}

/// `audio.transport` codes — `player.cmd`'s (the firmware's AUDIO.md, "Sources").
abstract final class Transport {
  static const play = 1;
  static const pause = 2;
  static const stop = 3;
  static const next = 4;
  static const previous = 5;
  static const toggle = 6;

  /// Bit of `audio.transport_caps` set while the position can be moved.
  static const seekBit = 128;

  static bool takes(int caps, int code) => caps & (1 << code) != 0;
}
