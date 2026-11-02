import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/panels.dart';
import 'package:streamer/state/providers.dart';

import 'support/fake_panel.dart';

/// One panel, one entry: a panel added by its address and found on the network is still one.
void main() {
  late MemorySettingsStore store;
  late MemorySecretStore secrets;
  late ProviderContainer container;

  setUp(() {
    store = MemorySettingsStore();
    secrets = MemorySecretStore();
    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        secretStoreProvider.overrideWithValue(secrets),
      ],
    );
  });
  tearDown(() => container.dispose());

  test('a panel goes by its host name; the entry that had it gives way, '
      'the login and the choice follow', () async {
    final panels = container.read(panelsProvider.notifier);
    await panels.put(
      const SavedPanel(id: 'modesp-2c4c', name: 'Old', host: '10.0.0.9'),
    );
    await panels.put(
      const SavedPanel(id: '192.0.2.7', name: 'Kitchen', host: '192.0.2.7'),
    );
    await container.read(activeIdProvider.notifier).set('192.0.2.7');
    await container
        .read(loginsProvider.notifier)
        .save('192.0.2.7', const PanelLogin('admin', 'test'));

    await panels.rename('192.0.2.7', 'modesp-2c4c');

    final list = container.read(panelsProvider);
    expect(list, hasLength(1));
    expect(list.single.id, 'modesp-2c4c');
    expect(list.single.host, '192.0.2.7', reason: 'the address that worked');
    expect(list.single.name, 'Kitchen');
    expect(container.read(activeIdProvider), 'modesp-2c4c');
    expect(secrets.values.keys, ['login:modesp-2c4c']);
    expect(
      SavedPanel.listFromJson(store.getString('panels')).single.id,
      'modesp-2c4c',
    );
  });

  test(
    'the panel saying its host name renames it, and it stays chosen',
    () async {
      final fake = FakePanel({
        'system.mdns_hostname': 'modesp-2c4c',
        'airplay.name': 'Kitchen',
      });
      await fake.start();
      addTearDown(fake.close);
      final id = '127.0.0.1:${fake.port}';
      await container
          .read(panelsProvider.notifier)
          .put(
            SavedPanel(id: id, name: id, host: '127.0.0.1', port: fake.port),
          );
      await container.read(activeIdProvider.notifier).set(id);
      container.listen(snapshotProvider, (_, _) {});

      await until(() => container.read(activeIdProvider) == 'modesp-2c4c');
      final saved = container.read(panelsProvider).single;
      expect(saved.name, 'Kitchen');
      expect(saved.port, fake.port);
      // and the panel is heard again under its new name
      await until(() => container.read(snapshotProvider).known);
      expect(container.read(snapshotProvider).hostname, 'modesp-2c4c');
    },
  );
}
