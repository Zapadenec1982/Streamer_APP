import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Android side of the volume buttons, as tests stand it in: [press] is a button pressed
/// (+1 up, -1 down), [intercepting] what the app last asked for.
class FakePhone {
  MockStreamHandlerEventSink? _sink;
  bool? intercepting;

  /// What the document picker hands back next: a file by its name and bytes, or none (cancelled).
  ({String name, Uint8List bytes})? picked;

  /// The MIME types the app last asked the picker for.
  List<String>? askedFor;

  /// The files the app saved, by name: what it wrote.
  final saved = <String, Uint8List>{};

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
    messenger.setMockMethodCallHandler(const MethodChannel('streamer/files'), (
      call,
    ) async {
      final args = (call.arguments as Map).cast<String, Object?>();
      switch (call.method) {
        case 'open':
          askedFor = (args['types']! as List).cast<String>();
          final file = picked;
          return file == null ? null : {'name': file.name, 'bytes': file.bytes};
        case 'save':
          saved[args['name']! as String] = args['bytes']! as Uint8List;
          return true;
      }
      return null;
    });
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
