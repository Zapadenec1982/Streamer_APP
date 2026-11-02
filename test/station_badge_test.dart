import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/ui/station_badge.dart';

/// The Dart disc against what the firmware's stationbadge.js says for the same names
/// (protocol/station_badges.json, computed by tool/station_badges.mjs).
void main() {
  final cases = (jsonDecode(
    File('protocol/station_badges.json').readAsStringSync(),
  ) as List).cast<Map<String, Object?>>();

  for (final c in cases) {
    test('«${c['name']}»', () {
      final want = (c['badge']! as Map).cast<String, Object?>();
      final got = StationBadge.of(c['name'] as String?);
      expect(got.label, want['label']);
      expect(got.first, want['first']);
      expect('#${got.color.toRadixString(16).padLeft(6, '0')}', want['color']);
    });
  }
}
