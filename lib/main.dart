import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'device/panels.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(
      allowList: SettingsKeys.all,
    ),
  );
  const secure = FlutterSecureStorage();
  final logins = <String, PanelLogin>{};
  for (final panel in SavedPanel.listFromJson(
    prefs.getString(SettingsKeys.panels),
  )) {
    final login = PanelLogin.fromJson(
      await secure.read(key: LoginsNotifier.key(panel.id)),
    );
    if (login != null) logins[panel.id] = login;
  }
  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(_PrefsStore(prefs)),
        secretStoreProvider.overrideWithValue(_SecureStore(secure)),
        initialLoginsProvider.overrideWithValue(logins),
      ],
      child: const StreamerApp(),
    ),
  );
}

class _SecureStore implements SecretStore {
  const _SecureStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class _PrefsStore implements SettingsStore {
  _PrefsStore(this._prefs);

  final SharedPreferencesWithCache _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
}
