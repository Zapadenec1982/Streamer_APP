import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Android side of the volume buttons, as tests stand it in: [press] is a button pressed
/// (+1 up, -1 down), [intercepting] what the app last asked for.
class FakePhone {
  MockStreamHandlerEventSink? _sink;
  bool? intercepting;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('streamer/volume_keys'),
      (call) async {
        if (call.method == 'intercept') intercepting = call.arguments as bool;
        return null;
      },
    );
    // the countries the tests name; any other stays its code
    messenger.setMockMethodCallHandler(
      const MethodChannel('streamer/regions'),
      (call) async {
        const uk = {'UA': 'Україна', 'PL': 'Польща', 'DE': 'Німеччина'};
        final codes = ((call.arguments as Map)['codes'] as List).cast<String>();
        return {for (final c in codes) c: uk[c] ?? c};
      },
    );
    messenger.setMockStreamHandler(
      const EventChannel('streamer/volume_keys/presses'),
      MockStreamHandler.inline(
        onListen: (_, events) {
          _sink = events;
        },
        onCancel: (_) {
          _sink = null;
        },
      ),
    );
  }

  void press(int step) => _sink?.success(step);
}
