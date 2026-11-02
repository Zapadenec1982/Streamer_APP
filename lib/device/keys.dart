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
  static const airplayName = StateKey<String>('airplay.name');
  static const airplayState = StateKey<String>('airplay.state');
  static const dlnaName = StateKey<String>('dlna.name');
  static const btPeer = StateKey<String>('bt.peer');
  static const playerCount = StateKey<int>('player.count');
  static const radioCount = StateKey<int>('radio.count');
  static const radioName = StateKey<String>('radio.name');
  static const usbAudioState = StateKey<String>('usb_audio.state');
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
    airplayName,
    airplayState,
    dlnaName,
    btPeer,
    playerCount,
    radioCount,
    radioName,
    usbAudioState,
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
