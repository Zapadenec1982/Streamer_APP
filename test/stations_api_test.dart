import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/device/panel/endpoint.dart';
import 'package:streamer/device/panel/panel_device_api.dart';
import 'package:streamer/device/panel/panel_link.dart';
import 'package:streamer/device/stations.dart';

import 'support/fake_panel.dart';

/// The station list and the catalogue against a panel on the loopback: what goes to it, in the
/// order the firmware reads it, and what comes back.
void main() {
  late FakePanel panel;
  late PanelDeviceApi api;

  setUp(() async {
    panel = FakePanel({'radio.list_rev': 3});
    await panel.start();
    api = PanelDeviceApi(
      PanelLink(
        PanelEndpoint('127.0.0.1', port: panel.port),
        timeout: const Duration(seconds: 2),
      ),
    );
    await until(() => api.current.known);
  });

  tearDown(() async {
    api.dispose();
    await panel.close();
  });

  Map<String, Object?> lastBody() =>
      (panel.requests.lastWhere((r) => r.method == 'POST').body! as Map)
          .cast<String, Object?>();

  test(
    'an edit goes whole, the generation first; the panel queues it (202) and '
    'moves list_rev',
    () async {
      final list = await api.stations();
      expect(await api.saveStations(list.remove(0)), StationsSave.saved);
      expect(lastBody().keys.toList(), ['rev', 'stations', 'presets']);
      await until(() => api.current.radio.listRev == 4);
      expect((await api.stations()).stations.single.name, 'Northbound FM');
    },
  );

  test('an edit from a list that moved meanwhile is refused (409)', () async {
    final list = await api.stations();
    await api.saveStations(list.rename(0, 'X'));
    expect(await api.saveStations(list.rename(0, 'Y')), StationsSave.changed);
  });

  test('a catalogue station: name, stream and uuid, the action last', () async {
    await api.catalogStation(
      name: 'Lviv Lamp FM',
      url: 'https://lamp.invalid/live',
      uuid: 'u1',
      act: 3,
    );
    expect(lastBody().keys.toList(), [
      'radio.web_name',
      'radio.web_url',
      'radio.web_uuid',
      'radio.web_act',
    ]);
    expect(lastBody()['radio.web_act'], 3);
  });

  test('the genres in each language; one without a tag is not one', () async {
    final genres = await api.radioGenres();
    expect(genres.single.tag, 'jazz');
    expect(genres.single.nameIn('uk'), 'Джаз');
    expect(genres.single.nameIn('de'), 'Jazz');
    expect(
      genres.single.nameIn('pl'),
      'Джаз',
      reason: 'Ukrainian where it has none',
    );
  });
}
