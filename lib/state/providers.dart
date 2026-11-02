import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/demo_device_api.dart';
import '../device/device_api.dart';
import '../device/models.dart';
import '../device/panel/panel_device_api.dart';
import '../device/panel/panel_link.dart';
import '../device/panels.dart';

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

/// Where panel logins live: the phone's secure storage, a map in tests.
abstract interface class SecretStore {
  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

final secretStoreProvider = Provider<SecretStore>((ref) => MemorySecretStore());

/// The logins main() read from secure storage before the app started, by panel id.
final initialLoginsProvider = Provider<Map<String, PanelLogin>>(
  (ref) => const {},
);

final loginsProvider =
    NotifierProvider<LoginsNotifier, Map<String, PanelLogin>>(
      LoginsNotifier.new,
    );

class LoginsNotifier extends Notifier<Map<String, PanelLogin>> {
  static String key(String id) => 'login:$id';

  @override
  Map<String, PanelLogin> build() => ref.watch(initialLoginsProvider);

  Future<void> save(String id, PanelLogin login) async {
    state = {...state, id: login};
    await ref.read(secretStoreProvider).write(key(id), login.toJson());
  }

  Future<void> forget(String id) async {
    state = {...state}..remove(id);
    await ref.read(secretStoreProvider).delete(key(id));
  }
}

/// The panels the app knows.
final panelsProvider = NotifierProvider<PanelsNotifier, List<SavedPanel>>(
  PanelsNotifier.new,
);

class PanelsNotifier extends Notifier<List<SavedPanel>> {
  static const _key = 'panels';

  @override
  List<SavedPanel> build() =>
      SavedPanel.listFromJson(ref.watch(settingsStoreProvider).getString(_key));

  /// Adds the panel, or updates the one with its id.
  Future<void> put(SavedPanel panel) async {
    final i = state.indexWhere((p) => p.id == panel.id);
    state = i < 0 ? [...state, panel] : ([...state]..[i] = panel);
    await ref
        .read(settingsStoreProvider)
        .setString(_key, SavedPanel.listToJson(state));
  }

  Future<void> forget(String id) async {
    state = state.where((p) => p.id != id).toList();
    await ref
        .read(settingsStoreProvider)
        .setString(_key, SavedPanel.listToJson(state));
    await ref.read(loginsProvider.notifier).forget(id);
    if (ref.read(activeIdProvider) == id) {
      await ref.read(activeIdProvider.notifier).set(null);
    }
  }
}

/// The id of the panel the app shows: a saved panel's, [PanelChoice.demoId], or null.
final activeIdProvider = NotifierProvider<ActiveIdNotifier, String?>(
  ActiveIdNotifier.new,
);

class ActiveIdNotifier extends Notifier<String?> {
  static const _key = 'active_panel';

  @override
  String? build() {
    final id = ref.watch(settingsStoreProvider).getString(_key);
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> set(String? id) async {
    state = id;
    await ref.read(settingsStoreProvider).setString(_key, id ?? '');
  }
}

/// The panel the app shows, with what is saved about it.
final activePanelProvider = Provider<PanelChoice>((ref) {
  final id = ref.watch(activeIdProvider);
  if (id == PanelChoice.demoId) return const DemoPanel();
  for (final p in ref.watch(panelsProvider)) {
    if (p.id == id) return RealPanel(p);
  }
  return const NoPanel();
});

/// The active panel's API. It follows the active panel's id only: the panel saying its name for
/// the first time renames it in the list without breaking the connection.
final deviceApiProvider = Provider<DeviceApi>((ref) {
  final id = ref.watch(activeIdProvider);
  final DeviceApi api;
  if (id == PanelChoice.demoId) {
    api = DemoDeviceApi();
  } else if (ref.read(panelsProvider).where((p) => p.id == id).firstOrNull
      case final panel?) {
    final login = ref.read(loginsProvider)[panel.id];
    final endpoint = login == null
        ? panel.endpoint
        : panel.endpoint.withLogin(login.user, login.password);
    final panelApi = PanelDeviceApi(PanelLink(endpoint));
    // the panel names itself once it has spoken: keep that name in the list
    final sub = panelApi.changes.listen((s) {
      if (s.known && s.name.isNotEmpty && s.name != panel.name) {
        final saved = ref
            .read(panelsProvider)
            .where((p) => p.id == panel.id)
            .firstOrNull;
        if (saved != null && saved.name != s.name) {
          unawaited(
            ref.read(panelsProvider.notifier).put(saved.copyWith(name: s.name)),
          );
        }
      }
    });
    ref.onDispose(sub.cancel);
    api = panelApi;
  } else {
    api = const NoPanelApi();
  }
  ref.onDispose(api.dispose);
  return api;
});

/// No panel chosen yet: a state that is nobody's.
class NoPanelApi implements DeviceApi {
  const NoPanelApi();

  static const _blank = DeviceSnapshot(
    name: '',
    scheme: 0,
    now: NowPlaying(kind: NowKind.off, title: LineLabel(CatalogLine.off)),
    cards: [],
    volume: 0,
    muted: false,
    known: false,
  );

  @override
  DeviceSnapshot get current => _blank;

  @override
  Stream<DeviceSnapshot> get changes => const Stream.empty();

  @override
  Future<void> setVolume(int percent) async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> transport(TransportAction action) async {}

  @override
  Future<void> selectSource(SourceId source) async {}

  @override
  void dispose() {}
}

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
