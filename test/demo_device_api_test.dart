import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/demo_art.dart';
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

  test('each track wears its own drawn cover, and the Player its shade', () async {
    final covers = <String>{};
    for (var i = 0; i < 4; i++) {
      final s = api.current;
      final key = s.now.coverKey!;
      covers.add(key);
      final art = DemoArt.of(key);
      expect(s.backdrop, art.backdrop);
      // at the firmware's lightness, 0.20, where the Player's light text reads
      final channels = [
        for (final shift in [16, 8, 0]) (s.backdrop! >> shift) & 0xFF,
      ];
      final lightness = (channels.reduce(max) + channels.reduce(min)) / 2 / 255;
      expect(lightness, closeTo(0.20, 0.01));
      await api.transport(TransportAction.next);
    }
    expect(covers, hasLength(4));
    // the same art from the same key, every run
    expect(DemoArt.of('art:3:1:Copper Lanterns').pattern, 1);
    expect(DemoArt.of('art:3:1:Copper Lanterns').palette, DemoArt.palettes[3]);
    expect(DemoArt.of('x').seed, DemoArt.of('x').seed);
  });

  test(
    'a station has no drawn cover and no shade: its disc stands in',
    () async {
      await api.selectSource(SourceId.radio);
      expect(api.current.backdrop, isNull);
    },
  );

  test('the backdrop is the firmware\'s: the hue at 20 % lightness, '
      'its saturation capped', () {
    // as the firmware's cover_backdrop() makes them (cover_tone.cpp)
    expect(coverBackdrop(0), 0);
    expect(coverBackdrop(0xFF0000), 0x4A1C1C);
    expect(coverBackdrop(0x808080), 0x333333);
  });
}
