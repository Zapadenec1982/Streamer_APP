import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/demo_device_api.dart';
import '../device/device_api.dart';
import '../device/eq.dart';
import '../device/keys.dart';
import '../device/models.dart';
import '../device/panel/panel_device_api.dart';
import '../device/panel/panel_link.dart';
import '../device/panels.dart';
import '../device/radio_browser.dart';
import '../device/speakers.dart';

/// Every setting the app keeps. The phone's store is opened with this list and refuses any other
/// key (SharedPreferencesWithCache's allowList, main.dart) — and so does the tests' store, so a key
/// the list forgot fails a test rather than a page on the phone.
abstract final class SettingsKeys {
  static const language = 'language';
  static const panels = 'panels';
  static const activePanel = 'active_panel';

  /// The catalogue's order, quality floor and «Лише Україна», kept between visits under the names
  /// the web keeps them by.
  static const catalogSort = 'radio.sort';
  static const catalogFloor = 'radio.floor';
  static const catalogUaOnly = 'radio.ua_only';

  static const all = {
    language,
    panels,
    activePanel,
    catalogSort,
    catalogFloor,
    catalogUaOnly,
  };
}

/// Where the app's own settings live: SharedPreferences on a phone, a map in tests.
abstract interface class SettingsStore {
  String? getString(String key);

  Future<void> setString(String key, String value);
}

class MemorySettingsStore implements SettingsStore {
  final _values = <String, String>{};

  @override
  String? getString(String key) => _values[_kept(key)];

  @override
  Future<void> setString(String key, String value) async =>
      _values[_kept(key)] = value;

  /// As the phone's store: a key not on the list is refused.
  static String _kept(String key) {
    if (!SettingsKeys.all.contains(key)) {
      throw ArgumentError.value(key, 'key', 'not in SettingsKeys.all');
    }
    return key;
  }
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
  static const _key = SettingsKeys.panels;

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

  /// A panel added by its address has said its mDNS host name: from now on it goes by that, as
  /// discovery knows it, so one panel stays one entry however it was added. An entry that already
  /// had that name gives way to this one — its address is the one that just worked. The login and
  /// the choice follow.
  Future<void> rename(String from, String to) async {
    final i = state.indexWhere((p) => p.id == from);
    if (i < 0 || from == to) return;
    final old = state[i];
    final moved = SavedPanel(
      id: to,
      name: old.name,
      host: old.host,
      port: old.port,
    );
    state = [
      for (final p in state)
        if (p.id == from) moved else if (p.id != to) p,
    ];
    await ref
        .read(settingsStoreProvider)
        .setString(_key, SavedPanel.listToJson(state));
    final logins = ref.read(loginsProvider.notifier);
    final login = ref.read(loginsProvider)[from];
    if (login != null) {
      await logins.save(to, login);
      await logins.forget(from);
    }
    if (ref.read(activeIdProvider) == from) {
      await ref.read(activeIdProvider.notifier).set(to);
    }
  }
}

/// The id of the panel the app shows: a saved panel's, [PanelChoice.demoId], or null.
final activeIdProvider = NotifierProvider<ActiveIdNotifier, String?>(
  ActiveIdNotifier.new,
);

class ActiveIdNotifier extends Notifier<String?> {
  static const _key = SettingsKeys.activePanel;

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
    // the panel names itself once it has spoken: keep that name in the list, and know the panel by
    // its host name from then on (a new connection, once, for one added by its address)
    final sub = panelApi.changes.listen((s) {
      if (!s.known) return;
      final panels = ref.read(panelsProvider.notifier);
      final saved = ref
          .read(panelsProvider)
          .where((p) => p.id == panel.id)
          .firstOrNull;
      if (saved == null) return;
      if (s.name.isNotEmpty && saved.name != s.name) {
        unawaited(panels.put(saved.copyWith(name: s.name)));
      }
      if (s.hostname.isNotEmpty && s.hostname != panel.id) {
        unawaited(panels.rename(panel.id, s.hostname));
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
  Future<void> seek(int seconds) async {}

  @override
  Future<void> setRepeat(int mode) async {}

  @override
  Future<void> setShuffle(bool on) async {}

  @override
  Future<LibraryPage> library({int from = 0, int count = 200}) async =>
      const LibraryPage(
        gen: 0,
        busy: false,
        count: 0,
        cursor: -1,
        root: '',
        from: 0,
        rows: [],
      );

  @override
  Future<void> playTrack(String path) async {}

  @override
  Future<DlnaView> dlnaView() async => const DlnaView(
    revision: 0,
    busy: false,
    servers: true,
    canBack: false,
    count: 0,
    next: false,
    previous: false,
    title: '',
    status: '',
    rows: [],
  );

  @override
  Future<void> dlnaCommand(int code) async {}

  @override
  Future<EqDoc> eq() async => const EqDoc(rev: 0, preset: '', presets: []);

  @override
  Future<int> setEqBands(int rev, List<EqBand> bands) async => rev;

  @override
  Future<void> chooseSound(String id) async {}

  @override
  Future<void> keepSound() async {}

  @override
  Future<void> setBass(int db) async {}

  @override
  Future<void> setTreble(int db) async {}

  @override
  Future<void> setLoudness(bool on) async {}

  @override
  Future<void> setEqOn(bool on) async {}

  @override
  Future<void> setLevelerSchedule({bool? on, int? from, int? to}) async {}

  @override
  Future<void> setVolMax(int percent) async {}

  @override
  Future<void> setVolStart(int percent) async {}

  @override
  Future<void> setAudio(AudioSetting setting, int value) async {}

  @override
  Future<void> setSpeakers(SpeakerWrite write) async {}

  @override
  Future<void> setPortMeter(bool on) async {}

  @override
  Future<void> setPortMeterChannel(int channel) async {}

  @override
  Future<({String status, double hz})> portMeterReading() async =>
      (status: '', hz: 0.0);

  @override
  Future<void> playTone({
    required int hz,
    ToneMode mode = ToneMode.chain,
    bool portOff = false,
    int? volCap,
  }) async {}

  @override
  Future<void> stopTone({SourceId? then, SpeakerWrite? write}) async {}

  @override
  Future<void> setLeveler(bool on) async {}

  @override
  Future<StationList> stations() async => const StationList(
    rev: 0,
    stations: [],
    presets: [-1, -1, -1, -1, -1, -1],
  );

  @override
  Future<void> listen(int index) async {}

  @override
  Future<void> storePreset(int slot) async {}

  @override
  Future<void> keepStation() async {}

  @override
  Future<StationsSave> saveStations(StationList edited) async =>
      StationsSave.saved;

  @override
  Future<void> catalogStation({
    required String name,
    required String url,
    String uuid = '',
    required int act,
  }) async {}

  @override
  Future<List<Genre>> radioGenres() async => const [];

  @override
  Uri? web(String route) => null;

  @override
  Future<Uint8List?> cover(String key) async => null;

  @override
  void suspend() {}

  @override
  void resume() {}

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
  static const _key = SettingsKeys.language;

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

/// Radio Browser, asked from the phone: the catalogue and the stations' logos (D12).
final radioBrowserProvider = Provider<RadioBrowser>((ref) {
  final rb = RadioBrowser();
  ref.onDispose(rb.close);
  return rb;
});
