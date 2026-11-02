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

  Future<void> selectSource(SourceId source);

  /// The picture of [NowPlaying.coverKey]; null when there is none to show.
  Future<Uint8List?> cover(String key);

  /// The app went to the background: let go of the panel (one of its three WebSocket slots).
  void suspend();

  /// The app is back: hear the panel again, starting from its whole state.
  void resume();

  void dispose();
}
