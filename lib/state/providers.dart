import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/demo_device_api.dart';
import '../device/device_api.dart';
import '../device/models.dart';

/// The active panel. Only the demo until the app speaks to a real one (plan, stage 2).
final deviceApiProvider = Provider<DeviceApi>((ref) {
  final api = DemoDeviceApi();
  ref.onDispose(api.dispose);
  return api;
});

/// The active panel's latest snapshot.
final snapshotProvider = NotifierProvider<SnapshotNotifier, DeviceSnapshot>(
  SnapshotNotifier.new,
);

class SnapshotNotifier extends Notifier<DeviceSnapshot> {
  @override
  DeviceSnapshot build() {
    final api = ref.watch(deviceApiProvider);
    final sub = api.changes.listen((snapshot) => state = snapshot);
    ref.onDispose(sub.cancel);
    return api.current;
  }
}

/// Where the app's own settings live: SharedPreferences on a phone, a map in tests.
abstract interface class SettingsStore {
  String? getString(String key);

  Future<void> setString(String key, String value);
}

class MemorySettingsStore implements SettingsStore {
  final _values = <String, String>{};

  @override
  String? getString(String key) => _values[key];

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;
}

/// Set by main() before the app starts.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => MemorySettingsStore(),
);

/// The app's language: the phone's, or one of the four the panel and the web speak.
enum AppLanguage {
  phone(null, null),
  uk('uk', 'Українська'),
  en('en', 'English'),
  de('de', 'Deutsch'),
  pl('pl', 'Polski');

  const AppLanguage(this.code, this.endonym);

  final String? code;

  /// The language's name in itself, as language pickers list them.
  final String? endonym;

  Locale? get locale => code == null ? null : Locale(code!);
}

final appLanguageProvider = NotifierProvider<AppLanguageNotifier, AppLanguage>(
  AppLanguageNotifier.new,
);

class AppLanguageNotifier extends Notifier<AppLanguage> {
  static const _key = 'language';

  @override
  AppLanguage build() {
    final code = ref.watch(settingsStoreProvider).getString(_key);
    return AppLanguage.values.firstWhere(
      (l) => l.name == code,
      orElse: () => AppLanguage.phone,
    );
  }

  Future<void> set(AppLanguage language) async {
    state = language;
    await ref.read(settingsStoreProvider).setString(_key, language.name);
  }
}
