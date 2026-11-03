import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/eq.dart';
import 'package:streamer/device/eq_file.dart';

/// Filters as text against what the firmware's own eqfile.js says (protocol/eq_cases.json,
/// tool/eq_cases.mjs): REW, Equalizer APO and AutoEQ lines read, counted and held to the
/// streamer's limits; the bands written back as such lines.
void main() {
  final c =
      ((jsonDecode(File('protocol/eq_cases.json').readAsStringSync()) as Map)
              .cast<String, Object?>()['files']!
          as Map);
  final sets =
      (jsonDecode(File('protocol/eq_cases.json').readAsStringSync())
              as Map)['sets']
          as Map;
  List<Map<String, Object?>> cases(String name) =>
      (c[name]! as List).cast<Map<String, Object?>>();

  for (final x in cases('parsed')) {
    test('read: ${x['name']}', () {
      final got = parseFilters(x['text']! as String);
      expect(got.bands, [
        for (final b in x['bands']! as List) EqBand.fromJson(b)!,
      ]);
      expect(
        got.preamp,
        x['preamp'] == null ? isNull : (x['preamp']! as num).toDouble(),
      );
      expect(
        (got.off, got.unsupported, got.unreadable, got.extra, got.clamped),
        (x['off'], x['unsupported'], x['unreadable'], x['extra'], x['clamped']),
      );
    });
  }

  test('written: the bands that are on, as APO and REW read them', () {
    for (final x in cases('written')) {
      final bands = [
        for (final b in sets[x['name']]! as List) EqBand.fromJson(b)!,
      ];
      expect(
        formatFilters(bands, 'P4 Player - ${x['name']}'),
        x['text'],
        reason: '${x['name']}',
      );
    }
  });

  test('a width in octaves and a shelf\'s slope as Q', () {
    for (final x in cases('widths')) {
      expect(
        bwToQ((x['octaves']! as num).toDouble()),
        closeTo((x['q']! as num).toDouble(), 1e-12),
      );
    }
    for (final x in cases('slopes')) {
      final q = slopeToQ(
        (x['slope']! as num).toDouble(),
        (x['gain']! as num).toDouble(),
      );
      if (x['q'] == null) {
        expect(q.isNaN, isTrue, reason: '$x');
      } else {
        expect(q, closeTo((x['q']! as num).toDouble(), 1e-12), reason: '$x');
      }
    }
  });

  test('written and read back, a set is the same set', () {
    for (final entry in sets.entries) {
      final bands = [for (final b in entry.value as List) EqBand.fromJson(b)!];
      final back = parseFilters(formatFilters(bands)).bands;
      expect(back, [
        for (final b in bands)
          if (b.on) b.clamped(),
      ], reason: '${entry.key}');
    }
  });
}
