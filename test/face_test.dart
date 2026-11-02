import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/face.dart';

/// The Dart face against what the firmware's now.js says for the same states
/// (protocol/now_faces.json, computed by tool/now_faces.mjs).
void main() {
  final cases = (jsonDecode(
    File('protocol/now_faces.json').readAsStringSync(),
  ) as List).cast<Map<String, Object?>>();

  test('the fixtures cover every source', () {
    final kinds = {for (final c in cases) (c['face']! as Map)['kind']};
    expect(
      kinds,
      containsAll([
        'off',
        'tone',
        'aux',
        'bt',
        'card',
        'radio',
        'dlna',
        'airplay',
        'usb',
      ]),
    );
  });

  for (final c in cases) {
    test(c['name']! as String, () {
      final state = (c['state']! as Map).cast<String, Object?>();
      expect(face(state).toJson(), c['face']);
    });
  }
}
