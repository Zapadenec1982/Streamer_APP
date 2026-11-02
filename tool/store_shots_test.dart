// The store's phone screenshots, made from the demo in Roboto at 1080×1920 (9:16):
//
//   flutter test tool/store_shots_test.dart
//
// They land in store/listing/<locale>/phone/<n>.png: the Player, the Sound sheet, a station and
// the Source page. Everything in them is the app's own — the demo's made-up tracks and its drawn
// covers.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/app.dart';
import 'package:streamer/device/demo_device_api.dart';
import 'package:streamer/device/device_api.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/state/providers.dart';

import '../test/support/fonts.dart';
import '../test/support/phone.dart';

// 480×853 dp: a large phone's width, so the Player fits whole in 9:16
const _ratio = 2.25;

void main() {
  setUpAll(loadPhoneFonts);

  for (final (locale, language) in [('en-US', 'en'), ('uk', 'uk')]) {
    testWidgets(locale, (tester) async {
      FakePhone().install();
      WidgetsApp.debugAllowBannerOverride = false;
      tester.view
        ..physicalSize = const Size(1080, 1920)
        ..devicePixelRatio = _ratio
        // a phone's status bar and gesture bar, without their icons
        ..padding = const FakeViewPadding(top: 72, bottom: 36)
        ..viewPadding = const FakeViewPadding(top: 72, bottom: 36);
      addTearDown(tester.view.reset);
      final api = DemoDeviceApi(autoTick: false);
      addTearDown(api.dispose);
      final store = MemorySettingsStore()
        ..setString('language', language)
        ..setString('active_panel', 'demo');
      final screen = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: screen,
          child: ProviderScope(
            overrides: [
              deviceApiProvider.overrideWithValue(api as DeviceApi),
              settingsStoreProvider.overrideWithValue(store),
            ],
            child: const StreamerApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var n = 0;
      Future<void> shoot() => tester.runAsync(() async {
        final boundary =
            screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: _ratio);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('store/listing/$locale/phone/${++n}.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });

      // the Player, then its Sound sheet
      await shoot();
      await tester.ensureVisible(find.byIcon(Icons.tune));
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await shoot();
      await tester.tapAt(const Offset(8, 120));
      await tester.pumpAndSettle();
      // a station, then the Source page
      await api.selectSource(SourceId.radio);
      api.tick(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await shoot();
      await tester.tap(find.byIcon(Icons.speaker_group_outlined));
      await tester.pumpAndSettle();
      await shoot();
    });
  }
}
