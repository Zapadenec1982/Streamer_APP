import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/app.dart';
import 'package:streamer/device/demo_device_api.dart';
import 'package:streamer/device/device_api.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/state/providers.dart';

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
    expect(find.text('Це — у вебінтерфейсі панелі'), findsOneWidget);
    expect(api.current.now.source, SourceId.bt);
  });

  // The web's layout was checked at 390×844, 390×664 and 360×740; the app keeps to the same.
  for (final (size, scale) in [
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
      await api.selectSource(SourceId.radio);
      await tester.pumpAndSettle();
    });
  }

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
    expect(find.text('Підключіть панель'), findsOneWidget);
    expect(find.text('Знайти панель'), findsOneWidget);
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
