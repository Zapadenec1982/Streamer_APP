import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/keys.dart';

/// The keys the app uses against the firmware's own list (protocol/state_meta.json,
/// tool/sync_state_meta.py).
void main() {
  final meta = (jsonDecode(
    File('protocol/state_meta.json').readAsStringSync(),
  ) as Map).cast<String, Map<String, Object?>>();

  for (final key in Keys.all.where((k) => !k.framework)) {
    test(key.name, () {
      final entry = meta[key.name];
      expect(
        entry,
        isNotNull,
        reason: '${key.name} is not a state key of the firmware',
      );
      expect(entry!['type'], key.metaType);
      expect(entry['access'] == 'readwrite', key.writable, reason: 'writable');
    });
  }

  for (final setting in AudioSetting.values) {
    test('${setting.name}: the range a slider moves in is the firmware\'s', () {
      final entry = meta[setting.key.name]!;
      expect(
        (entry['min'], entry['max'], entry['step']),
        (setting.min, setting.max, setting.step),
      );
    });
  }

  test('every key the face reads is one the firmware has', () {
    final source = File('lib/device/face.dart').readAsStringSync();
    final read = RegExp(r"s\['([a-z_]+\.[a-z_0-9]+)'\]")
        .allMatches(source)
        .map((m) => m[1]!)
        .toSet();
    expect(read, isNotEmpty);
    expect(read.difference(meta.keys.toSet()), isEmpty);
  });
}
