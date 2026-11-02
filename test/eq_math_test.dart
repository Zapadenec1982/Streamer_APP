import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/eq.dart';
import 'package:streamer/device/eq_math.dart';

/// The app's EQ maths against the firmware: the curve against the vectors the audio core's own
/// design writes (protocol/eq_curve_vectors.json — the web's eqmath.js is held to the same file),
/// the edits and the whole system against what the web's eqband.js and syscurve.js say
/// (protocol/eq_cases.json, tool/eq_cases.mjs).
void main() {
  Map<String, Object?> load(String name) =>
      (jsonDecode(File('protocol/$name').readAsStringSync()) as Map)
          .cast<String, Object?>();
  EqBand band(Object? json) => EqBand.fromJson(json)!;
  List<double> numbers(Object? json) => [
    for (final v in json! as List) (v as num).toDouble(),
  ];

  group('the firmware\'s vectors', () {
    final v = load('eq_curve_vectors.json');
    final freqs = numbers(v['freqs']);
    for (final c in (v['cases']! as List).cast<Map<String, Object?>>()) {
      final fs = (c['fs']! as num).toDouble();
      final bands = [for (final b in c['bands']! as List) band(b)];
      test('${c['name']}: each band, matched and bilinear', () {
        for (var i = 0; i < bands.length; i++) {
          final matched = numbers((c['band_db']! as List)[i]);
          final bilinear = numbers((c['bilinear_db']! as List)[i]);
          final d = bands[i].on
              ? designBand(bands[i], fs, matched: false)
              : null;
          for (var j = 0; j < freqs.length; j++) {
            expect(
              bandMagnitudeDb(bands[i], fs, freqs[j]),
              closeTo(matched[j], 1e-6),
              reason: 'band $i at ${freqs[j]} Hz',
            );
            expect(
              d == null ? 0 : svfMagnitudeDb(d, fs, freqs[j]),
              closeTo(bilinear[j], 1e-6),
              reason: 'band $i bilinear at ${freqs[j]} Hz',
            );
          }
        }
      });
      test('${c['name']}: the summed curve', () {
        // The glass evaluates its curve in float: a thousandth of a dB away, and below −48 dB
        // rounding noise (edges_*: a 20 kHz high pass on a 20 Hz low pass sits at −150 dB).
        double clamp(double x) => x.clamp(-48, 48).toDouble();
        final want = numbers(c['curve_db']);
        final got = curveDb(bands, fs, freqs);
        for (var j = 0; j < freqs.length; j++) {
          expect(
            clamp(got[j]),
            closeTo(clamp(want[j]), 1e-3),
            reason: 'at ${freqs[j]} Hz',
          );
        }
      });
    }
  });

  group('the web\'s edits and system curve', () {
    final c = load('eq_cases.json');
    final freqs = numbers(c['freqs']);
    final sets = {
      for (final e in (c['sets']! as Map).entries)
        e.key as String: [for (final b in e.value as List) band(b)],
    };

    test('a new band goes where no band is', () {
      for (final f in (c['free']! as List).cast<Map<String, Object?>>()) {
        final bands = sets[f['name']]!;
        expect(freeFrequency(bands), f['free'], reason: '${f['name']}');
        final added = addBand(bands);
        final want = f['added'] as Map?;
        if (want == null) {
          expect(added, isNull, reason: '${f['name']}');
        } else {
          expect(added!.i, want['i'], reason: '${f['name']}');
          expect(added.bands[added.i], band(want['band']));
          expect(added.bands.sublist(0, added.i), bands);
        }
      }
    });

    test('a band is held to the panel\'s limits', () {
      for (final x in (c['clamp']! as List).cast<Map<String, Object?>>()) {
        expect(band(x['band']).clamped(), band(x['clamped']));
      }
    });

    test('a new type keeps what it can of the band', () {
      for (final x in (c['retype']! as List).cast<Map<String, Object?>>()) {
        final to = EqType.values.byName(x['to']! as String);
        expect(band(x['band']).withType(to), band(x['out']), reason: '$x');
      }
    });

    test('a pass\'s slope is on the ladder', () {
      for (final x in (c['pass_q']! as List).cast<Map<String, Object?>>()) {
        expect(passQIndex((x['q']! as num).toDouble()), x['i'], reason: '$x');
      }
    });

    for (final x in (c['stages']! as List).cast<Map<String, Object?>>()) {
      test('the whole system: ${x['name']}', () {
        final s = (x['s']! as Map).cast<String, Object?>();
        double n(String k) => (s[k]! as num).toDouble();
        final stages = systemStages(
          bass: n('bass'),
          treble: n('treble'),
          loudDb: n('loudDb'),
          hpHz: n('hpHz'),
          portHz: n('portHz'),
          liftDb: n('liftDb'),
        );
        final want = (x['stages']! as List).cast<Map<String, Object?>>();
        expect(stages.length, want.length);
        for (var i = 0; i < want.length; i++) {
          expect(stages[i].band, band(want[i]), reason: 'stage $i');
          expect(stages[i].bilinear, want[i]['bilinear'] == true);
        }
        final curve = systemCurveDb(
          sets[x['eq']]!,
          stages,
          (x['fs']! as num).toDouble(),
          freqs,
          eqOn: x['eqOn'] == true,
        );
        final wantCurve = numbers(x['curve']);
        for (var j = 0; j < freqs.length; j++) {
          expect(curve[j], closeTo(wantCurve[j], 1e-9), reason: '${freqs[j]}');
        }
      });
    }
  });

  test('a number that is not one is the band\'s default', () {
    const odd = EqBand(
      type: EqType.highshelf,
      f: double.nan,
      gain: double.infinity,
      q: double.nan,
    );
    expect(
      odd.clamped(),
      const EqBand(type: EqType.highshelf, f: 1000, gain: 0, q: 1),
    );
  });
}
