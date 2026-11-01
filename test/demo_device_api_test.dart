import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/demo_device_api.dart';
import 'package:streamer/device/models.dart';

void main() {
  late DemoDeviceApi api;

  setUp(() => api = DemoDeviceApi(autoTick: false));
  tearDown(() => api.dispose());

  String title(DeviceSnapshot s) => (s.now.title as TextLabel).text;

  test('starts on Bluetooth, playing a track from the phone', () {
    final now = api.current.now;
    expect(now.source, SourceId.bt);
    expect(now.playing, isTrue);
    expect(now.device, DemoDeviceApi.phoneName);
    expect(now.canToggle && now.canPrevious && now.canNext, isTrue);
    expect(api.current.cards.where((c) => c.active).single.card, SourceCard.bt);
  });

  test('volume is kept within 0…100 and every change is reported', () async {
    final seen = <int>[];
    final sub = api.changes.listen((s) => seen.add(s.volume));
    await api.setVolume(140);
    await api.setVolume(-3);
    await api.setVolume(55);
    await pumpEventQueue();
    expect(seen, [100, 0, 55]);
    await sub.cancel();
  });

  test('toggle pauses and plays; next and previous change the track', () async {
    final first = title(api.current);
    await api.transport(TransportAction.toggle);
    expect(api.current.now.playing, isFalse);
    await api.transport(TransportAction.next);
    expect(title(api.current), isNot(first));
    expect(api.current.now.playing, isTrue);
    await api.transport(TransportAction.previous);
    expect(title(api.current), first);
  });

  test('time moves the track on, and the end of a track starts the next', () {
    final start = api.current.now.position!;
    api.tick(const Duration(seconds: 5));
    expect(api.current.now.position, start + const Duration(seconds: 5));
    final first = title(api.current);
    api.tick(const Duration(minutes: 10));
    expect(title(api.current), isNot(first));
    expect(api.current.now.position, Duration.zero);
  });

  test(
    'a station connects first, then shows what it plays; it has no play/pause',
    () async {
      await api.selectSource(SourceId.radio);
      var now = api.current.now;
      expect(now.source, SourceId.radio);
      expect((now.subtitle! as LineLabel).line, CatalogLine.connecting);
      expect(now.canToggle, isFalse);
      expect(now.duration, isNull);
      api.tick(const Duration(seconds: 2));
      now = api.current.now;
      expect(now.subtitle, isA<TextLabel>());
      expect(now.format, isNotEmpty);
    },
  );

  test('AirPlay and USB wait for a sender, named by the panel', () async {
    await api.selectSource(SourceId.airplay);
    final pick = api.current.now.subtitle! as LineLabel;
    expect(pick.line, CatalogLine.airplayPick);
    expect(pick.name, DemoDeviceApi.panelName);
    expect(api.current.now.canToggle || api.current.now.canNext, isFalse);
    await api.selectSource(SourceId.usb);
    expect((api.current.now.title as LineLabel).line, CatalogLine.usbWaiting);
  });

  test('the playing card says what plays; the others say what they have', () {
    final cards = {for (final c in api.current.cards) c.card: c.status};
    expect((cards[SourceCard.bt]! as TextLabel).text, title(api.current));
    expect(
      (cards[SourceCard.radio]! as LineLabel).count,
      DemoDeviceApi.stationCount,
    );
    expect(
      (cards[SourceCard.card]! as LineLabel).count,
      DemoDeviceApi.cardTrackCount,
    );
    expect((cards[SourceCard.servers]! as LineLabel).line, CatalogLine.servers);
  });
}
