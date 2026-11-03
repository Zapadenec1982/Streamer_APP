/// Filters as text: the lines Equalizer APO reads, Room EQ Wizard writes and reads (its "Generic"
/// equaliser), and AutoEQ publishes for headphones — a port of the firmware's
/// webui/src/lib/eqfile.js, held to it by protocol/eq_cases.json:
///
///     Preamp: -6.4 dB
///     Filter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.71
///     Filter  2: ON  PK       Fc   47.0 Hz  Gain  -0.7 dB  Q  0.39
///     Filter 3: OFF None
///     Filter: ON PEQ Fc 100 Hz Gain 1.0 dB BW Oct 0.167
///
/// The number after Filter means nothing (APO ignores it). What the streamer has: PK, PEQ, Modal
/// (a peak), LSC and LS (a low shelf by its centre frequency), HSC and HS, LP and LPQ, HP and HPQ,
/// NO. A shelf's slope in dB per octave ("LSC 10.8 dB") becomes the RBJ Q for that slope at its
/// gain; without a slope or a Q it is 12 dB/oct, Q 0.707, as REW's shelves are. LS/HS 6dB and 12dB
/// are shelves by their corner, which the streamer does not have, and BP, AP and IIR are not
/// filters it has: counted, not read. OFF lines are skipped. A Preamp is said and not kept: the
/// streamer keeps headroom for a boost itself. Up to [EqLimits.bands] filters; numbers out of its
/// reach are held to it, and counted.
library;

import 'dart:math' as math;

import 'eq.dart';

const _typeOf = {
  'PK': EqType.peak,
  'PEQ': EqType.peak,
  'MODAL': EqType.peak,
  'LS': EqType.lowshelf,
  'LSC': EqType.lowshelf,
  'HS': EqType.highshelf,
  'HSC': EqType.highshelf,
  'LP': EqType.lowpass,
  'LPQ': EqType.lowpass,
  'HP': EqType.highpass,
  'HPQ': EqType.highpass,
  'NO': EqType.notch,
};

const _codeOf = {
  EqType.peak: 'PK',
  EqType.lowshelf: 'LSC',
  EqType.highshelf: 'HSC',
  EqType.lowpass: 'LPQ',
  EqType.highpass: 'HPQ',
  EqType.notch: 'NO',
};

const _num = r'([-+]?\d+(?:[.,]\d+)?)';
final _filter = RegExp(
  r'^\s*Filter\s*\d*\s*:\s*(ON|OFF)\b\s*(.*)$',
  caseSensitive: false,
);
final _preamp = RegExp('^\\s*Preamp\\s*:\\s*$_num\\s*dB', caseSensitive: false);
final _fc = RegExp('\\bFc\\s+$_num\\s*(kHz|Hz)?', caseSensitive: false);
final _gain = RegExp('\\bGain\\s+$_num', caseSensitive: false);
final _q = RegExp('\\bQ\\s+$_num', caseSensitive: false);
final _bw = RegExp('\\bBW\\s+(?:Oct\\s+)?$_num', caseSensitive: false);
final _code = RegExp(r'^([A-Za-z]+)(?:\s+(\d+(?:[.,]\d+)?)\s*dB\b)?');

double _number(String s) => double.parse(s.replaceFirst(',', '.'));

/// A peak's bandwidth in octaves as its Q.
double bwToQ(double octaves) =>
    math.sqrt(math.pow(2, octaves)) / (math.pow(2, octaves) - 1);

/// A shelf's slope in dB/oct at its gain as its RBJ Q (S = slope / 12); NaN where there is none.
double slopeToQ(double slopeDb, double gainDb) {
  final s = slopeDb / 12;
  final a = math.pow(10, gainDb / 40);
  return 1 / math.sqrt((a + 1 / a) * (1 / s - 1) + 2);
}

/// What a text of filters holds: the bands to import (on, held to the streamer's limits), the
/// Preamp in dB or null, and how many lines were OFF, of a kind the streamer lacks, not readable,
/// past [EqLimits.bands], and how many filters had a number held.
class FilterText {
  FilterText();

  final bands = <EqBand>[];
  double? preamp;
  int off = 0;
  int unsupported = 0;
  int unreadable = 0;
  int extra = 0;
  int clamped = 0;
}

bool _same(double a, double b) => (a - b).abs() < 1e-9;

FilterText parseFilters(String text) {
  final out = FilterText();
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final pre = _preamp.firstMatch(line);
    if (pre != null) {
      out.preamp = _number(pre[1]!);
      continue;
    }
    final m = _filter.firstMatch(line);
    // headers, notes, comments
    if (m == null) continue;
    if (m[1]!.toUpperCase() == 'OFF') {
      out.off++;
      continue;
    }
    final rest = m[2]!;
    final t = _code.firstMatch(rest);
    if (t == null) {
      out.unreadable++;
      continue;
    }
    final code = t[1]!.toUpperCase();
    // REW's unused filter
    if (code == 'NONE') {
      out.off++;
      continue;
    }
    final slope = t[2] != null ? _number(t[2]!) : null;
    final type = _typeOf[code];
    // LS/HS with 6 or 12 dB right after: shelves by their corner, not the centre the streamer uses
    if (type == null || ((code == 'LS' || code == 'HS') && slope != null)) {
      out.unsupported++;
      continue;
    }
    final fc = _fc.firstMatch(rest);
    if (fc == null) {
      out.unreadable++;
      continue;
    }
    final f = _number(fc[1]!) * (fc[2]?.toLowerCase() == 'khz' ? 1000 : 1);
    final g = _gain.firstMatch(rest);
    final gain = type.hasGain ? (g != null ? _number(g[1]!) : double.nan) : 0.0;
    if (type.hasGain && !gain.isFinite) {
      out.unreadable++;
      continue;
    }
    final qm = _q.firstMatch(rest);
    final bw = _bw.firstMatch(rest);
    var q = qm != null
        ? _number(qm[1]!)
        : bw != null
        ? bwToQ(_number(bw[1]!))
        : double.nan;
    if (!q.isFinite) {
      if (type.isShelf) {
        q = slope != null ? slopeToQ(slope, gain) : EqLimits.qBw12;
        // steeper than a shelf here goes: held to it below
        if (!q.isFinite) q = double.infinity;
      } else if (type.isPass) {
        q = EqLimits.qBw12;
      } else {
        // a peak or a notch says its width
        out.unreadable++;
        continue;
      }
    }
    if (!f.isFinite || !(q > 0)) {
      out.unreadable++;
      continue;
    }
    if (out.bands.length >= EqLimits.bands) {
      out.extra++;
      continue;
    }
    final want = EqBand(type: type, f: f, gain: gain, q: q);
    final b = want.clamped();
    if (!_same(b.f, want.f) ||
        !_same(b.gain, want.gain) ||
        !_same(b.q, want.q)) {
      out.clamped++;
    }
    out.bands.add(b);
  }
  return out;
}

/// A number as short as it can be without losing what the streamer keeps of it, as JavaScript
/// writes `Number(v.toFixed(places))`.
String _short(double v, int places) {
  final x = double.parse(v.toStringAsFixed(places));
  return x == x.truncateToDouble() ? '${x.toInt()}' : '$x';
}

/// The bands that are on, as the lines above: Fc to a hundredth of a Hz, gain to a hundredth of a
/// dB, Q to a thousandth — what the streamer itself calls the same band (eq_same_section).
/// [title] goes on the first line, after a #.
String formatFilters(List<EqBand> bands, [String title = '']) {
  final lines = <String>[if (title.isNotEmpty) '# $title'];
  var n = 0;
  for (final b in bands) {
    final code = _codeOf[b.type];
    if (!b.on || code == null) continue;
    n++;
    final gain = b.type.hasGain ? ' Gain ${_short(b.gain, 2)} dB' : '';
    lines.add(
      'Filter $n: ON $code Fc ${_short(b.f, 2)} Hz$gain Q ${_short(b.q, 3)}',
    );
  }
  return '${lines.join('\n')}\n';
}
