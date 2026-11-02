import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/app.dart';
import 'package:streamer/device/demo_device_api.dart';
import 'package:streamer/device/device_api.dart';
import 'package:streamer/device/eq.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/device/panel/panel_link.dart';
import 'package:streamer/device/radio_browser.dart';
import 'package:streamer/device/speakers.dart';
import 'package:streamer/state/providers.dart';
import 'package:streamer/ui/eq_plot.dart';
import 'package:streamer/ui/player_page.dart';
import 'package:streamer/ui/sound_sheet.dart';
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

/// The demo whose list always moves on just before an edit lands: 409, every time.
class MovedListDemo extends CountingDemo {
  @override
  Future<StationsSave> saveStations(StationList edited) async =>
      StationsSave.changed;
}

/// The catalogue without the internet: two stations, three countries; what was asked, kept.
class FakeRadioBrowser extends RadioBrowser {
  FakeRadioBrowser() : super(base: 'http://catalogue.invalid');

  final asked = <CatalogQuery>[];

  @override
  Future<({List<CatalogStation> rows, bool more})> stations(
    CatalogQuery query, {
    CatalogSort sort = CatalogSort.popular,
    CatalogFloor floor = CatalogFloor.k128,
    bool uaOnly = false,
    int offset = 0,
  }) async {
    asked.add(query);
    return (
      rows: const [
        CatalogStation(
          name: 'Lviv Lamp FM',
          url: 'https://lamp.invalid/live',
          uuid: '11111111-1111-1111-1111-111111111111',
          codec: 'MP3',
          bitrate: 192,
          countryCode: 'UA',
          clicks: 1200,
        ),
        CatalogStation(
          name: 'Kyiv Night Jazz',
          url: 'https://night.invalid/live',
          codec: 'FLAC',
          countryCode: 'UA',
          clicks: 300,
        ),
      ],
      more: false,
    );
  }

  @override
  Future<List<({String code, int count})>> countries() async => const [
    (code: 'UA', count: 900),
    (code: 'PL', count: 600),
    (code: 'DE', count: 1500),
  ];

  @override
  Future<Map<String, String>> favicons(Iterable<String> uuids) async =>
      const {};
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

  /// A section by its place in the navigation bar: a page's own title can be the same word.
  Finder tab(String name) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(name),
  );

  /// Scrolls the page in front — the one a finger reaches — until [target] is on the screen;
  /// [up] for one above.
  Future<void> reveal(
    WidgetTester tester,
    Finder target, {
    bool up = false,
  }) async {
    await tester.scrollUntilVisible(
      target,
      up ? -200 : 200,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    await tester.pumpAndSettle();
  }

  /// The Player's «Звук» sheet, then its way to the equalizer.
  Future<void> openEq(WidgetTester tester) async {
    await tester.tap(find.text('Звук'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Еквалайзер'));
    await tester.pumpAndSettle();
  }

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

  testWidgets('the media servers card opens their browser: servers, folders, '
      'a track that plays', (tester) async {
    await pumpApp(tester);
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await tester.tap(find.text('Джерело'));
    await tester.pumpAndSettle();
    // rows are named by their tiles: the mini-player shows what the phone plays meanwhile
    await tester.tap(find.text('Медіасервери'));
    await settle();
    expect(find.text('Медіасервери DLNA'), findsOne);
    // none found yet: the page looks for them by itself, as the glass does
    expect(find.text('Attic NAS'), findsOne);
    await tester.tap(find.widgetWithText(ListTile, 'Attic NAS'));
    await settle();
    expect(find.text('Music'), findsOne);
    await tester.tap(find.widgetWithText(ListTile, 'Live Recordings'));
    await settle();
    expect(find.text('Формат не підтримується'), findsOne);
    // the path: «Медіасервери › Attic NAS › Live Recordings»; a crumb climbs back up
    await tester.tap(find.widgetWithText(TextButton, 'Attic NAS'));
    await settle();
    await tester.tap(find.widgetWithText(ListTile, 'Music'));
    await settle();
    await tester.tap(find.widgetWithText(ListTile, 'Lantern Theory'));
    await settle();
    await tester.tap(find.widgetWithText(ListTile, 'Amber Hours'));
    await settle();
    await tester.tap(find.widgetWithText(ListTile, 'Morning Static'));
    await settle();
    expect(api.current.now.kind, NowKind.dlna);
    expect(
      find.text('Morning Static'),
      findsOne,
      reason: 'the Player shows it',
    );
    expect(find.text('Медіасервери DLNA'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the card\'s library: every track, a filter, a tap plays one', (
    tester,
  ) async {
    await api.selectSource(SourceId.card);
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Бібліотека картки'));
    await tester.pumpAndSettle();
    expect(find.text('16 треків'), findsOne);
    expect(find.text('01 Glasshouse'), findsOne);
    await tester.enterText(find.byType(TextField), 'orchard');
    await tester.pumpAndSettle();
    expect(find.text('4 з 16'), findsOne);
    await tester.tap(find.text('03 Last Ferry'));
    await tester.pumpAndSettle();
    expect(api.current.now.title, isA<TextLabel>());
    expect((api.current.now.title as TextLabel).text, 'Last Ferry');
    expect(find.text('Бібліотека картки'), findsNothing);
  });

  testWidgets(
    'the card\'s queue: shuffle and repeat, and a slider that seeks',
    (tester) async {
      await api.selectSource(SourceId.card);
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Повтор вимкнено'));
      await tester.pumpAndSettle();
      expect(api.current.now.repeat, 1);
      expect(find.byTooltip('Повтор одного треку'), findsOne);
      await tester.tap(find.byTooltip('Випадковий порядок'));
      await tester.pumpAndSettle();
      expect(api.current.now.shuffle, isTrue);
      // the first slider is the track's
      await tester.drag(find.byType(Slider).first, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(api.current.now.position, greaterThan(Duration.zero));
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'the mini-player: what plays, on the other pages; its button; a tap '
    'opens the Player',
    (tester) async {
      await pumpApp(tester);
      expect(find.text('Lantern Theory'), findsOne, reason: 'the Player only');
      await tester.tap(find.text('Джерело'));
      await tester.pumpAndSettle();
      // the artist's line is the mini-player's: the card says the title
      expect(find.text('Lantern Theory'), findsOne);
      await tester.tap(find.byTooltip('Пауза'));
      await tester.pumpAndSettle();
      expect(api.current.now.playing, isFalse);
      expect(
        find.byTooltip('Грати'),
        findsOne,
        reason: 'it can resume, so it stays',
      );
      await tester.tap(find.text('Lantern Theory'));
      await tester.pumpAndSettle();
      expect(find.text('BLUETOOTH'), findsOne);
    },
  );

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
      // Тембр і гучність as long as it gets, the equalizer, a band's sheet
      await api.setLevelerSchedule(on: true);
      await tester.tap(tab('Налаштування'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Тембр і гучність'));
      await tester.tap(find.text('Тембр і гучність'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Еквалайзер'));
      await tester.tap(find.text('Еквалайзер'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ще'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Показати всю систему'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('High Shelf'));
      await tester.tap(find.text('High Shelf'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Готово'));
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      // Колонки, its details, the port page both ways, Тонке налаштування, the wizard's two steps
      // with its help open — and a test tone's bar over the navigation all the while
      await api.playTone(hz: 40);
      Future<void> settings(String row) async {
        await tester.tap(tab('Налаштування'));
        await tester.pumpAndSettle();
        // the list keeps where it was scrolled to: from its top
        await tester.fling(
          find.byType(Scrollable).hitTestable().first,
          const Offset(0, 2000),
          3000,
        );
        await tester.pumpAndSettle();
        await reveal(tester, find.text(row));
        await tester.tap(find.text(row));
        await tester.pumpAndSettle();
      }

      await settings('Колонки');
      await reveal(tester, find.text('Подробиці'));
      await tester.tap(find.text('Подробиці'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Знайти частоту вручну'));
      await tester.tap(find.text('Знайти частоту вручну'));
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('~45 с'));
      await reveal(tester, find.text('Вручну'), up: true);
      await tester.tap(find.text('Вручну'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Записати 40 Гц'));
      await settings('Тонке налаштування');
      await reveal(tester, find.text('Підйом басу'));
      await settings('Колонки');
      await reveal(tester, find.text('Налаштувати'));
      await tester.tap(find.text('Налаштувати'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('З фазоінвертором'));
      await tester.tap(find.text('З фазоінвертором'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Не знаю — як перевірити'));
      await tester.tap(find.text('Не знаю — як перевірити'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Далі'));
      await tester.tap(find.text('Далі'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Пропустити'));
      // what the meter found, with its table
      await reveal(tester, find.text('Почати'), up: true);
      await tester.tap(find.text('Почати'));
      await tester.pumpAndSettle();
      api.tick(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Лишити як було'));
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
    await api.setLevelerSchedule(on: true);
    await tester.tap(find.text('Тембр і гучність'));
    await tester.pumpAndSettle();
    await check();
    await reveal(tester, find.text('Еквалайзер'));
    await tester.tap(find.text('Еквалайзер'));
    await tester.pumpAndSettle();
    await check();
    await tester.tap(find.text('Low Shelf'));
    await tester.pumpAndSettle();
    await check();
    // Колонки, the wizard, the port page, Тонке налаштування — the tone's bar over them
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    await api.playTone(hz: 40);
    for (final row in ['Колонки', 'Тонке налаштування']) {
      await tester.tap(tab('Налаштування'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text(row));
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await check();
    }
    await tester.tap(tab('Налаштування'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Колонки'));
    await tester.tap(find.text('Колонки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Налаштувати'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('З фазоінвертором'));
    await tester.pumpAndSettle();
    await check();
    await tester.tap(find.text('Далі'));
    await tester.pumpAndSettle();
    await check();
    await tester.tap(find.text('Знайти вручну'));
    await tester.pumpAndSettle();
    await check();
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
      expect((await api.eq()).preset, 'jazz');
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
    // a tap on a station plays it, and the page stays for the next, as the web's does
    await tester.tap(find.widgetWithText(ListTile, 'Cedar Jazz'));
    await tester.pumpAndSettle();
    expect(api.current.radio.current, 2);
    expect(find.text('Станції'), findsOneWidget);
  });

  testWidgets(
    'the list edited: renamed, moved, onto a preset, deleted, a stream '
    'added — each sent whole and the next waits for it',
    (tester) async {
      await api.selectSource(SourceId.radio);
      await pumpApp(tester);
      await tester.tap(find.text('Усі станції · 12'));
      await tester.pumpAndSettle();
      Future<void> more(String name) async {
        await tester.tap(find.byTooltip('Дії зі станцією «$name»'));
        await tester.pumpAndSettle();
      }

      Future<List<String>> names() async => [
        for (final s in (await api.stations()).stations) s.name,
      ];

      await more('Cedar Jazz');
      await tester.enterText(
        find.widgetWithText(TextField, 'Cedar Jazz'),
        'Cedar',
      );
      await tester.tap(find.text('Зберегти'));
      await tester.pumpAndSettle();
      expect((await names())[2], 'Cedar');
      await more('Cedar');
      await tester.tap(find.text('Вище'));
      await tester.pumpAndSettle();
      expect((await names()).take(3), [
        'Radio Lantern',
        'Cedar',
        'Northbound FM',
      ]);
      expect((await api.stations()).presets.take(3), [
        0,
        2,
        1,
      ], reason: 'presets follow');
      await more('Amber Wave');
      await tester.tap(find.widgetWithText(ChoiceChip, '6'));
      await tester.pumpAndSettle();
      expect((await api.stations()).presets[5], 4);
      await more('Amber Wave');
      await tester.tap(find.text('Видалити'));
      await tester.pumpAndSettle();
      expect(await names(), isNot(contains('Amber Wave')));
      expect((await api.stations()).presets[5], -1);
      // the station that plays is not deleted
      await more('Radio Lantern');
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Видалити'))
            .onPressed,
        isNull,
      );
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Додати потік'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Адреса потоку'),
        'ftp://x',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Додати потік'));
      await tester.pumpAndSettle();
      expect(
        find.text('Потрібна адреса, що починається з http:// або https://'),
        findsOne,
      );
      await tester.tap(find.byTooltip('Додати потік'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Адреса потоку'),
        'https://stream.invalid/live',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Додати потік'));
      await tester.pumpAndSettle();
      expect(
        (await names()).last,
        'stream.invalid',
        reason: 'no name: its host',
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('an edit made from a list that has moved is refused, and the '
      'moved list shown', (tester) async {
    api.dispose();
    api = MovedListDemo();
    await api.selectSource(SourceId.radio);
    await pumpApp(tester);
    await tester.tap(find.text('Усі станції · 12'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Дії зі станцією «Cedar Jazz»'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Нижче'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Список змінився на стрімері — показую новий, повторіть правку',
      ),
      findsOne,
    );
    expect(find.text('Cedar Jazz'), findsWidgets);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the catalogue: Ukraine\'s top, a station played, kept, put on a '
      'preset; the countries; the genres', (tester) async {
    final catalogue = FakeRadioBrowser();
    await api.selectSource(SourceId.radio);
    await tester.binding.setSurfaceSize(const Size(412, 892));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceApiProvider.overrideWithValue(api as DeviceApi),
          settingsStoreProvider.overrideWithValue(store),
          radioBrowserProvider.overrideWithValue(catalogue),
        ],
        child: const StreamerApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Усі станції · 12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Топ'));
    await tester.pumpAndSettle();
    expect(find.text('Україна'), findsOne);
    expect(catalogue.asked.last, isA<ByCountry>());
    await tester.tap(find.text('Lviv Lamp FM'));
    await tester.pumpAndSettle();
    expect((api.current.now.title as TextLabel).text, 'Lviv Lamp FM');
    expect(api.current.radio.keepable, isTrue);
    await tester.tap(find.byTooltip('В улюблені').first);
    await tester.pumpAndSettle();
    expect((await api.stations()).stations.last.name, 'Lviv Lamp FM');
    await tester.tap(find.byTooltip('На кнопку').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '5'));
    await tester.pumpAndSettle();
    final list = await api.stations();
    expect(list.stations[list.presets[4]].name, 'Kyiv Night Jazz');
    // the countries, named in the app's language
    await tester.tap(find.text('Країни'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Польща'));
    await tester.pumpAndSettle();
    expect((catalogue.asked.last as ByCountry).code, 'PL');
    await tester.tap(find.byTooltip('Країни'));
    await tester.pumpAndSettle();
    expect(find.text('Німеччина'), findsOne);
    // the genres, from the streamer
    await tester.tap(find.text('Жанри'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Джаз'));
    await tester.pumpAndSettle();
    expect((catalogue.asked.last as ByTag).tag, 'jazz');
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

  testWidgets('the equalizer from the Player\'s sheet: the bands in a list; a '
      'step in a band\'s sheet is heard, and the sound becomes «Власний»', (
    tester,
  ) async {
    await pumpApp(tester);
    await openEq(tester);
    expect(find.byType(EqPlot), findsOne);
    expect(find.text('Low Shelf'), findsOne);
    expect(find.text('+4,9 дБ'), findsOne);
    await tester.tap(find.text('Low Shelf'));
    await tester.pumpAndSettle();
    expect(find.text('Смуга 1'), findsOne);
    await tester.tap(find.byTooltip('Більше').first);
    await tester.pumpAndSettle();
    final doc = await api.eq();
    expect(doc.preset, 'custom');
    expect(doc.bands.first.f, 42.4, reason: 'a twelfth of an octave up');
    expect(find.text('42 Гц'), findsWidgets);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Власний'), findsOne);
    // the whole system, dashed over the curve
    await tester.tap(find.byTooltip('Ще'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Показати всю систему'));
    await tester.pumpAndSettle();
    expect(find.text('Пунктир — уся система'), findsOne);
  });

  testWidgets('a point on the plot moves its band, and «Скасувати» puts it '
      'and the sound back; a finger off the points moves nothing', (
    tester,
  ) async {
    await pumpApp(tester);
    await openEq(tester);
    final plot = find.byType(EqPlot);
    final width = tester.getSize(plot).width;
    await tester.dragFrom(
      tester.getTopLeft(plot) + Offset(width - 14, 110),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    expect((await api.eq()).preset, 'rock');
    // where the point is now: the page may have scrolled under that finger
    final point =
        tester.getTopLeft(plot) +
        eqPointAt((await api.eq()).bands, 4, 48000, width);
    final finger = await tester.startGesture(point);
    for (var i = 0; i < 4; i++) {
      await finger.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await finger.up();
    await tester.pumpAndSettle();
    final moved = await api.eq();
    expect(moved.preset, 'custom');
    expect(moved.bands[4].f, 500, reason: 'straight up: the same frequency');
    expect(moved.bands[4].gain, greaterThan(-4.2));
    expect(find.textContaining('Смуга 5: 500 Гц'), findsOne);
    await tester.tap(find.text('Скасувати'));
    await tester.pumpAndSettle();
    final back = await api.eq();
    expect(back.preset, 'rock');
    expect(back.bands[4].gain, -4.2);
  });

  testWidgets('«Власний»: a band added where no band is; «Скинути» turns every '
      'band off, «Повернути» puts them back', (tester) async {
    await api.chooseSound('custom');
    await pumpApp(tester);
    await openEq(tester);
    await reveal(tester, find.text('+ Додати смугу'));
    await tester.tap(find.text('+ Додати смугу'));
    await tester.pumpAndSettle();
    expect(find.text('Смуга 4'), findsOne);
    var doc = await api.eq();
    expect(doc.bands, hasLength(4));
    expect(doc.bands[3], const EqBand(type: EqType.peak, f: 450));
    await tester.tap(find.text('Увімкнена'));
    await tester.pumpAndSettle();
    expect((await api.eq()).bands[3].on, isFalse);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Вимк.'), findsOne);
    await reveal(tester, find.text('Скинути «Власний»'));
    await tester.tap(find.text('Скинути «Власний»'));
    await tester.pumpAndSettle();
    doc = await api.eq();
    expect(doc.bands.any((b) => b.on), isFalse);
    await tester.tap(find.text('Повернути'));
    await tester.pumpAndSettle();
    doc = await api.eq();
    expect(doc.bands.where((b) => b.on), hasLength(3));
  });

  testWidgets('Тембр і гучність: «Максимум» with its «Скасувати», the start '
      'volume, and the leveler by the clock on a step of 5 minutes', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(tab('Налаштування'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тембр і гучність'));
    await tester.pumpAndSettle();
    final maximum = find.byType(Slider).at(2);
    await tester.drag(maximum, const Offset(-120, 0));
    await tester.pumpAndSettle();
    final lowered = api.current.sound.volMax!;
    expect(lowered, lessThan(100));
    expect(find.text('Максимум: 100 % → $lowered %'), findsOne);
    await tester.tap(find.text('Скасувати'));
    await tester.pumpAndSettle();
    expect(api.current.sound.volMax, 100);
    await tester.tap(find.text('Після увімкнення'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не гучніше 30 %'));
    await tester.pumpAndSettle();
    expect(api.current.sound.volStart, 30);
    expect(find.text('Не гучніше 30 %'), findsOne);
    await reveal(tester, find.text('За розкладом'));
    await tester.tap(find.text('За розкладом'));
    await tester.pumpAndSettle();
    expect(api.current.sound.levSchedule, isTrue);
    await reveal(tester, find.text('Вимикати о'));
    expect(find.text('22:00'), findsOne);
    expect(find.text('07:00'), findsOne);
    // the phone's own clock face; the same time back writes nothing
    await tester.tap(find.text('Вмикати о'));
    await tester.pumpAndSettle();
    final ok = MaterialLocalizations.of(tester.element(find.byType(Dialog)))
        .okButtonLabel;
    await tester.tap(find.text(ok));
    await tester.pumpAndSettle();
    expect(api.current.sound.levFrom, 22 * 60);
    // a time picked goes on the schedule's step of 5 minutes
    expect(scheduleMinutes(const TimeOfDay(hour: 23, minute: 7)), 1385);
    expect(scheduleMinutes(const TimeOfDay(hour: 7, minute: 3)), 425);
    expect(scheduleMinutes(const TimeOfDay(hour: 23, minute: 58)), 1435);
    expect(scheduleMinutes(const TimeOfDay(hour: 0, minute: 2)), 0);
  });

  testWidgets('Колонки: closed speakers are set in one step, and the page '
      'says so', (tester) async {
    await pumpApp(tester);
    await tester.tap(tab('Налаштування'));
    await tester.pumpAndSettle();
    expect(find.text('Тип колонок не обрано'), findsOne);
    await tester.tap(find.text('Колонки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Налаштувати'));
    await tester.pumpAndSettle();
    expect(find.text('1 з 2'), findsOne);
    await tester.tap(find.text('Закриті'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(api.current.speakers.setup.type, SpeakerType.closed);
    // the title, and the details' line under it
    expect(find.text('Закриті колонки'), findsNWidgets(2));
    expect(find.text('Налаштувати знову'), findsOne);
  });

  testWidgets('Колонки: the port measured by the streamer\'s microphone is '
      'written only on «Прийняти»', (tester) async {
    await pumpApp(tester);
    await tester.tap(tab('Налаштування'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Колонки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Налаштувати'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('З фазоінвертором'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Далі'));
    await tester.pumpAndSettle();
    expect(find.text('2 з 2'), findsOne);
    await tester.tap(find.text('Права'));
    await tester.pumpAndSettle();
    expect(api.current.speakers.meterChannel, 2);
    await tester.tap(find.text('Почати'));
    await tester.pumpAndSettle();
    expect(api.current.speakers.measuring, isTrue);
    // the sweep, half way, read as the page reads it: every 2 s
    api.tick(const Duration(seconds: 14));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('50 %'), findsOne);
    api.tick(const Duration(seconds: 14));
    await tester.pumpAndSettle();
    expect(find.text('Частота фазоінвертора — 47 Гц'), findsOne);
    expect(
      api.current.speakers.setup.type,
      SpeakerType.unset,
      reason: 'not yet',
    );
    await tester.tap(find.text('Прийняти'));
    await tester.pumpAndSettle();
    final setup = api.current.speakers.setup;
    expect(
      (setup.type, setup.portHz, setup.source),
      (SpeakerType.ported, 47, PortSource.measured),
    );
    expect(find.text('Фазоінвертор 47 Гц · виміряно'), findsOne);
  });

  testWidgets('the port by hand: a tone with the port off and the volume '
      'capped, stepped up, written — and the source that played is back', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(tab('Налаштування'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Колонки'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Подробиці'));
    await tester.tap(find.text('Подробиці'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Знайти частоту вручну'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вручну'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Встановити'));
    await tester.pumpAndSettle();
    expect(api.current.tone.on, isTrue);
    expect(api.current.tone.hz, 40);
    expect(
      find.text('Тест-тон'),
      findsOne,
      reason: 'the bar over the navigation',
    );
    await reveal(tester, find.byTooltip('Вище'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Вище'));
      await tester.pumpAndSettle();
    }
    expect(api.current.tone.hz, 43, reason: 'heard as it steps');
    await reveal(tester, find.text('Записати 43 Гц'));
    await tester.tap(find.text('Записати 43 Гц'));
    await tester.pumpAndSettle();
    expect(api.current.tone.on, isFalse);
    expect(api.current.now.source, SourceId.bt);
    final setup = api.current.speakers.setup;
    expect(
      (setup.type, setup.portHz, setup.source),
      (SpeakerType.ported, 43, PortSource.manual),
    );
    expect(find.text('Фазоінвертор 43 Гц'), findsOne);
  });

  testWidgets('a test tone shows on every page, and its bar stops it', (
    tester,
  ) async {
    await api.playTone(hz: 1000);
    await pumpApp(tester);
    await tester.tap(tab('Джерело'));
    await tester.pumpAndSettle();
    expect(find.text('1000 Гц · через DSP'), findsOne);
    await tester.tap(find.byTooltip('Зупинити'));
    await tester.pumpAndSettle();
    expect(api.current.tone.on, isFalse);
    expect(api.current.now.source, SourceId.off);
    expect(find.text('Тест-тон'), findsNothing);
  });

  testWidgets('Тонке налаштування: the sliders that follow the port, and the '
      'balance on Колонки', (tester) async {
    await pumpApp(tester);
    await tester.tap(tab('Налаштування'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тонке налаштування'));
    await tester.pumpAndSettle();
    // no port: the subsonic is the person's, the lift has nothing to lift
    expect(find.text('40 Гц'), findsOne);
    final lift = tester.widget<Slider>(find.byType(Slider).last);
    expect(lift.onChanged, isNull);
    await tester.drag(find.byType(Slider).at(2), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(api.current.sound.width, lessThan(100));
    await api.setSpeakers(
      const SpeakerWrite(
        SpeakerType.ported,
        portHz: 45,
        source: PortSource.manual,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('36 Гц · від фазоінвертора'), findsOne);
    expect(
      tester.widget<Slider>(find.byType(Slider).last).onChanged,
      isNotNull,
    );
    await tester.tap(
      find.byTooltip(
        MaterialLocalizations.of(tester.element(find.byType(Scaffold).last))
            .backButtonTooltip,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Колонки'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Баланс'));
    await tester.drag(find.byType(Slider).first, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(api.current.speakers.balanceDb10, greaterThan(0));
    expect(find.textContaining('Правіше · '), findsWidgets);
  });
}
