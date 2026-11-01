import 'models.dart';

/// A panel as the app sees it. Implementations: `DemoDeviceApi` now; the panel's own API later
/// (plan, stage 2). The app sends a command and shows what the panel then reports — it never
/// assumes a command took effect, and nothing is queued while the panel is away.
abstract interface class DeviceApi {
  /// The panel now.
  DeviceSnapshot get current;

  /// Every later change.
  Stream<DeviceSnapshot> get changes;

  Future<void> setVolume(int percent);

  Future<void> setMuted(bool muted);

  Future<void> transport(TransportAction action);

  Future<void> selectSource(SourceId source);

  void dispose();
}
