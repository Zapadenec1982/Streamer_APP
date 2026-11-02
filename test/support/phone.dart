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
