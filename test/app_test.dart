import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/app.dart';
import 'package:streamer/device/demo_device_api.dart';
import 'package:streamer/device/device_api.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/device/panel/panel_link.dart';
import 'package:streamer/state/providers.dart';
import 'package:streamer/ui/player_page.dart';
import 'package:streamer/ui/station_card.dart';

import 'support/phone.dart';

/// The demo, counting how often the app lets go of it and takes it back.
class CountingDemo extends DemoDeviceApi {
  CountingDemo() : super(autoTick: false);

  int suspended = 0;
  int resumed = 0;

  @override
  void suspend() {
    suspended++;
    super.suspend();
  }

  @override
  void resume() {
    resumed++;
    super.resume();
  }
}

/// A panel that has gone: the mute never reaches it.
class FailingDemo extends CountingDemo {
  @override
  Future<void> setMuted(bool muted) => Future.error(const PanelError(0));
}

/// The demo with a station whose first word is long, on a preset.
class LongNamesDemo extends CountingDemo {
  @override
  Future<StationList> stations() async => const StationList(
    rev: 1,
    stations: [
      Station(name: 'Radio Lantern', url: 'http://a.invalid/1'),
      Station(name: 'Nightride FM', url: 'http://a.invalid/2'),
      Station(name: 'Harbour Lights FM', url: 'http://a.invalid/3'),
    ],
    presets: [0, 1, 2, -1, -1, -1],
  );
}

/// A panel slow to take a volume: each write lands when the test says so, and only then does the
/// panel report it.
class SlowVolumeDemo extends CountingDemo {
  final writes = <int>[];
  final landing = <Completer<void>>[];

  @override
  Future<void> setVolume(int percent) async {
    writes.add(percent);
    final done = Completer<void>();
    landing.add(done);
    await done.future;
    await super.setVolume(percent);
  }
}

/// A panel that never answers: no state, ever, and the link trying all the while.
class SilentPanel extends NoPanelApi {
  int suspended = 0;
  int resumed = 0;

  @override
  DeviceSnapshot get current => const DeviceSnapshot(
    name: '',
    scheme: 0,
    now: NowPlaying(kind: NowKind.off, title: LineLabel(CatalogLine.off)),
    cards: [],
    volume: 0,
    muted: false,
    status: LinkStatus.connecting,
    known: false,
  );

  @override
  void suspend() => suspended++;

  @override
  void resume() => resumed++;
}

void main() {
  late CountingDemo api;
  late MemorySettingsStore store;
  late FakePhone phone;

  setUp(() {
    api = CountingDemo();
    phone = FakePhone()..install();
    store = MemorySettingsStore();
    store.setString('language', 'uk');
    store.setString('active_panel', 'demo');
  });
  tearDown(() => api.dispose());

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(412, 892),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceApiProvider.overrideWithValue(api as DeviceApi),
          settingsStoreProvider.overrideWithValue(store),
        ],
        child: const StreamerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('three sections; the Player shows what the phone plays', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Плеєр'), findsOneWidget);
    expect(find.text('Джерело'), findsOneWidget);
    expect(find.text('Налаштування'), findsOneWidget);
    expect(find.text('BLUETOOTH'), findsOneWidget);
    expect(find.text('Amber Hours'), findsOneWidget);
    expect(find.text('LHDC V5 96 кГц'), findsOneWidget);
  });

  testWidgets('play/pause and mute reach the panel and come back', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Пауза'));
    await tester.pumpAndSettle();
    expect(api.current.now.playing, isFalse);
    expect(find.byTooltip('Грати'), findsOneWidget);
    await tester.tap(find.byTooltip('Вимкнути звук'));
    await tester.pumpAndSettle();
    expect(api.current.muted, isTrue);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
  });

  testWidgets('a card on the Source page switches the source', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Джерело'));
    await tester.pumpAndSettle();
    expect(find.text('Чекає на iPhone чи Mac'), findsOneWidget);
    await tester.tap(find.text('AirPlay'));
    await tester.pumpAndSettle();
    expect(api.current.now.source, SourceId.airplay);
    await tester.tap(find.text('Плеєр'));
    await tester.pumpAndSettle();
    expect(find.text('Очікую пристрій'), findsOneWidget);
    expect(find.text('Оберіть «ModESP» на телефоні'), findsOneWidget);
  });

  testWidgets('the media servers card points to the web instead of switching', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Джерело'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Медіасервери'));
    await tester.pump();
    expect(find.text('Це — у вебінтерфейсі стрімера'), findsOneWidget);
    expect(api.current.now.source, SourceId.bt);
  });

  // The web's layout was checked at 390×844, 390×664 and 360×740; the app keeps to the same, and
  // to Android's largest text (200 %), here as a plain ×2 — harder than Android's own scaling,
  // which grows large text less.
  for (final (size, scale) in [
    (const Size(412, 892), 2.0),
    (const Size(360, 740), 2.0),
    (const Size(412, 892), 1.6),
    (const Size(360, 740), 1.3),
    (const Size(390, 664), 1.0),
  ]) {
    testWidgets('every page fits at $size with text ×$scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, size: size);
      for (final section in ['Джерело', 'Налаштування', 'Плеєр']) {
        await tester.tap(find.text(section));
        await tester.pumpAndSettle();
      }
      // the sheet, as tall as it gets
      await tester.ensureVisible(find.text('Звук'));
      await tester.tap(find.text('Звук'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      await api.selectSource(SourceId.radio);
      api.tick(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Усі станції · 12'));
      await tester.tap(find.text('Усі станції · 12'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('a long word on a preset moves the presets fewer to a row, '
      'never breaks in the middle', (tester) async {
    api.dispose();
    api = LongNamesDemo();
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester);
    await api.selectSource(SourceId.radio);
    api.tick(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final presets = find.byType(StationPresets);
    final grid = tester.widget<GridView>(
      find.descendant(of: presets, matching: find.byType(GridView)),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, lessThan(3));
    final name = tester.renderObject<RenderParagraph>(
      find.descendant(of: presets, matching: find.text('Nightride FM')),
    );
    // «Nightride» stays on one line
    final word = name.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 9),
    );
    expect(word.map((box) => box.top).toSet(), hasLength(1));
  });

  testWidgets('TalkBack hears the Player in words, a stop for each thing', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    // spoken in its own case, with the phone it comes from
    expect(find.bySemanticsLabel(RegExp(r'^Bluetooth\nPhone$')), findsOne);
    // the title, the artist and the format: one stop
    expect(
      find.bySemanticsLabel(RegExp(r'^Amber Hours\nLantern Theory\nLHDC')),
      findsOne,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Позиція в треку')),
      isSemantics(value: '0:56 з 3:42'),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Гучність')),
      isSemantics(
        value: '32%',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('TalkBack moves Bass a step at a time and hears it signed', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    await tester.tap(find.text('Звук'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Бас')),
      isSemantics(value: '+2', increasedValue: '+3'),
    );
    tester.semantics.performAction(
      find.semantics.byLabel('Бас'),
      SemanticsAction.increase,
    );
    await tester.pumpAndSettle();
    expect(api.current.sound.bass, 3);
    semantics.dispose();
  });

  testWidgets('TalkBack: a preset says its number, its station and what a tap '
      'and a hold do', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    await api.selectSource(SourceId.radio);
    api.tick(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('кнопка 1, Radio Lantern')),
      isSemantics(
        isButton: true,
        isSelected: true,
        hasTapAction: true,
        hasLongPressAction: true,
        onTapHint: 'слухати',
        onLongPressHint: 'зберегти сюди те, що грає',
      ),
    );
    expect(find.bySemanticsLabel('кнопка 4, Зберегти сюди'), findsOne);
    semantics.dispose();
  });

  testWidgets('every page keeps Android\'s rules: 48 dp targets, each with a '
      'name, text that reads', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    Future<void> check() async {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }

    await check();
    await tester.tap(find.text('Звук'));
    await tester.pumpAndSettle();
    await check();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await api.selectSource(SourceId.radio);
    api.tick(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await check();
    for (final section in ['Джерело', 'Налаштування']) {
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
      await check();
    }
    semantics.dispose();
  });

  testWidgets('the volume slider stays where the finger left it, and writes '
      'one value at a time', (tester) async {
    api.dispose();
    final slow = SlowVolumeDemo();
    api = slow;
    await pumpApp(tester);
    final slider = find.byType(Slider).first;
    double shown() => tester.widget<Slider>(slider).value;
    final gesture = await tester.startGesture(tester.getCenter(slider));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await gesture.up();
    await tester.pump();
    final left = shown();
    expect(slow.writes, hasLength(1), reason: 'the first is still on its way');
    expect(slow.current.volume, 32, reason: 'the panel has not moved yet');
    expect(
      left,
      greaterThan(32),
      reason: 'the finger\'s value, not the panel\'s',
    );
    // the first lands: the newest goes next, and the slider does not step back meanwhile
    slow.landing.last.complete();
    await tester.pump();
    expect(shown(), left);
    expect(slow.writes, [slow.writes.first, left.round()]);
    slow.landing.last.complete();
    await tester.pump(const Duration(seconds: 3));
    expect(slow.current.volume, left.round());
    expect(shown(), left.round());
  });

  testWidgets('the Player wears the cover\'s colour as the web does: from the '
      'top, fading into the page', (tester) async {
    await pumpApp(tester);
    final box = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byType(PlayerPage),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final gradient =
        (box.decoration! as BoxDecoration).gradient! as RadialGradient;
    expect(gradient.center, Alignment.topCenter);
    expect(gradient.colors.first, Color(0xFF000000 | api.current.backdrop!));
  });

  testWidgets('a panel that does not answer says so, with a retry and the '
      'other panels', (tester) async {
    final silent = SilentPanel();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceApiProvider.overrideWithValue(silent),
          settingsStoreProvider.overrideWithValue(store),
        ],
        child: const StreamerApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Підключення…'), findsOne);
    await tester.pump(const Duration(seconds: 11));
    expect(find.text("Немає зв'язку зі стрімером"), findsOne);
    // at once, not at the end of the backoff
    final resumed = silent.resumed;
    await tester.tap(find.text('Повторити'));
    await tester.pump();
    expect(silent.suspended, 1);
    expect(silent.resumed, resumed + 1);
    expect(find.text('Підключення…'), findsOne);
    await tester.pump(const Duration(seconds: 11));
    await tester.tap(find.text('Інший стрімер'));
    await tester.pumpAndSettle();
    expect(find.text('Демо-стрімер'), findsOne);
  });

  testWidgets(
    'in the background the app lets go of the panel; back, it takes it again',
    (tester) async {
      await pumpApp(tester);
      final resumedAtStart = api.resumed;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(api.suspended, 1);
      expect(phone.intercepting, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(api.resumed, resumedAtStart + 1);
      expect(phone.intercepting, isTrue);
    },
  );

  testWidgets('the phone\'s volume buttons step the panel\'s volume', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(phone.intercepting, isTrue);
    // the presses come over a platform channel, outside the test's clock; the 150 ms the app
    // gathers them for runs on it
    Future<void> press(List<int> steps) async {
      await tester.runAsync(() async {
        steps.forEach(phone.press);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 200));
    }

    await press([1, 1]);
    expect(api.current.volume, 36);
    await press([-1]);
    expect(api.current.volume, 34);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a run of presses shows one popup that follows it, then none', (
    tester,
  ) async {
    await pumpApp(tester);
    final popup = find.bySemanticsLabel(RegExp(r'^Гучність \d+$'));
    Future<void> press() => tester.runAsync(() async {
      phone.press(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    // one press, then the button held: Android repeats it every ~50 ms, a frame every 16
    await press();
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await press();
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(popup, findsOneWidget);
    expect(find.bySemanticsLabel('Гучність 42'), findsOneWidget);
    expect(api.current.volume, 42);
    // not a popup for each press, one after another, once the volume is there
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
  });

  testWidgets('writes that fail in a run say so once, not once each', (
    tester,
  ) async {
    api.dispose();
    api = FailingDemo();
    await pumpApp(tester);
    final said = find.text("Немає зв'язку зі стрімером");
    await tester.tap(find.byTooltip('Вимкнути звук'));
    await tester.pumpAndSettle();
    expect(said, findsOneWidget);
    // two more while the first is still up
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Вимкнути звук'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(said, findsOneWidget);
    // its 4 s, and none waiting behind it
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(said, findsNothing);
  });

  testWidgets(
    'the Sound sheet: a sound, Bass, Treble, loudness, the way to the equalizer',
    (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Звук'));
      await tester.pumpAndSettle();
      expect(find.text('Бас'), findsOneWidget);
      expect(find.text('Високі'), findsOneWidget);
      expect(find.text('Тонкомпенсація'), findsOneWidget);
      expect(find.text('Еквалайзер'), findsOneWidget);
      await tester.tap(find.byType(DropdownMenu<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Джаз').last);
      await tester.pumpAndSettle();
      expect((await api.soundPresets()).preset, 'jazz');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(api.current.sound.loudness, isFalse);
    },
  );

  testWidgets('the moon turns the night leveler on and off', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Вирівнювання гучності'));
    await tester.pumpAndSettle();
    expect(api.current.sound.leveler, isTrue);
  });

  testWidgets('a station: its name between ‹ ›, the presets, every station', (
    tester,
  ) async {
    await pumpApp(tester);
    await api.selectSource(SourceId.radio);
    api.tick(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Radio Lantern'), findsWidgets);
    expect(
      find.byTooltip('Пауза'),
      findsNothing,
      reason: 'a station has no transport row',
    );
    // a tap on a preset tunes it
    await tester.tap(find.text('Northbound FM'));
    await tester.pumpAndSettle();
    expect(api.current.radio.current, 1);
    // a hold on an empty one stores what plays
    await tester.longPress(find.text('Зберегти сюди').first);
    await tester.pumpAndSettle();
    expect((await api.stations()).presets[3], 1);
    await tester.tap(find.text('Усі станції · 12'));
    await tester.pumpAndSettle();
    expect(find.text('Станції'), findsOneWidget);
    await tester.tap(find.text('Cedar Jazz'));
    await tester.pumpAndSettle();
    expect(api.current.radio.current, 2);
    expect(find.text('Станції'), findsNothing);
  });

  testWidgets('with no panel yet: what to do, and the demo a tap away', (
    tester,
  ) async {
    store.setString('active_panel', '');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
        child: const StreamerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Підключіть стрімер'), findsOneWidget);
    expect(find.text('Знайти стрімер'), findsOneWidget);
    await tester.tap(find.text('Спробувати демо'));
    await tester.pumpAndSettle();
    expect(find.text('BLUETOOTH'), findsOneWidget);
    expect(store.getString('active_panel'), 'demo');
    // the demo's ticking clock is the app's own here; stop it
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the language is the app\'s own setting and is kept', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Налаштування'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мова'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(store.getString('language'), 'en');
  });
}
