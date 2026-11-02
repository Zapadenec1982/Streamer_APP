import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/app.dart';
import 'package:streamer/device/demo_device_api.dart';
import 'package:streamer/device/device_api.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/state/providers.dart';
import 'package:streamer/ui/player_page.dart';

import 'support/fonts.dart';
import 'support/phone.dart';

/// The Player on the customer's Pixel, measured in Roboto: 1080×2340 at 356 dpi (485×1052 dp),
/// the system text at 180 % — here as a plain ×1.8, harder than Android's own scaling, which grows
/// large text less.
void main() {
  setUpAll(loadPhoneFonts);

  for (final radio in [false, true]) {
    testWidgets('the ${radio ? 'radio' : 'Bluetooth'} Player fits the screen '
        'without scrolling', (tester) async {
      FakePhone().install();
      tester.view
        ..physicalSize = const Size(1080, 2340)
        ..devicePixelRatio = 356 / 160
        ..padding = const FakeViewPadding(top: 71, bottom: 53)
        ..viewPadding = const FakeViewPadding(top: 71, bottom: 53);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = DemoDeviceApi(autoTick: false);
      addTearDown(api.dispose);
      final store = MemorySettingsStore()
        ..setString('language', 'uk')
        ..setString('active_panel', 'demo');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceApiProvider.overrideWithValue(api as DeviceApi),
            settingsStoreProvider.overrideWithValue(store),
          ],
          child: const StreamerApp(),
        ),
      );
      if (radio) {
        await api.selectSource(SourceId.radio);
        api.tick(const Duration(seconds: 2));
      }
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(PlayerPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.maxScrollExtent, 0);
    });
  }
}
