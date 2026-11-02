/// The EQ as the panel holds it, and the edits the app makes on a set of bands: a port of the
/// firmware's webui/src/lib/eqband.js. A band is the API's `{type, f, gain, q, on}` (GET and POST
/// /api/eq, modules/audio/src/eq_http.inc); a set has up to [EqLimits.bands], and «Рівно» is the
/// same ten with all of them off.
///
/// The app lists every band of the set by its place, on or off, as the glass does: «Смуга 4» is
/// the point 4 on both, and «Увімкнена» in a band's sheet turns it on and off with its numbers
/// kept. protocol/eq_cases.json holds these edits to what eqband.js does.
library;

import 'dart:math' as math;

/// A band's kind, by the API's names, in BandType's order (audio_dsp/dsp_chain.h) — the glass's
/// list and the band sheet's.
enum EqType {
  peak,
  lowshelf,
  highshelf,
  lowpass,
  highpass,
  notch;

  bool get isShelf => this == lowshelf || this == highshelf;

  bool get isPass => this == lowpass || this == highpass;

  /// Does a gain mean anything for this type? Not for a pass or a notch (screen_eq.cpp).
  bool get hasGain => this == peak || isShelf;
}

/// The panel's limits (eq_web.h, dsp_chain.h): what the editors reach, and what the panel holds a
/// band it is sent to.
abstract final class EqLimits {
  static const fMin = 20.0;
  static const fMax = 20000.0;
  static const gainMax = 12.0;
  static const qMin = 0.3;
  static const qMax = 8.0;

  /// A shelf takes Q up to this: above it a shelf overshoots its own gain.
  static const shelfQMax = 1.0;

  /// Linkwitz-Riley 12 dB/oct.
  static const qLr12 = 0.5;

  /// Butterworth 12 dB/oct.
  static const qBw12 = 0.707;

  /// The bands a set holds at most (dsp_chain.h MAX_BANDS).
  static const bands = 10;

  /// The ladder a pass band's slope walks (screen_eq.cpp PASS_Q): both named alignments on it.
  static const passQ = [
    0.3, 0.4, qLr12, 0.6, qBw12, 0.8, 1.0, 1.3, 1.6, 2.0, 2.5, 3.0, 4.0, //
    5.0, 6.5, 8.0,
  ];
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

class EqBand {
  const EqBand({
    required this.type,
    required this.f,
    this.gain = 0,
    this.q = 1,
    this.on = true,
  });

  final EqType type;

  /// Hz.
  final double f;

  /// dB; nothing for a pass or a notch ([EqType.hasGain]).
  final double gain;
  final double q;
  final bool on;

  EqBand copyWith({
    EqType? type,
    double? f,
    double? gain,
    double? q,
    bool? on,
  }) => EqBand(
    type: type ?? this.type,
    f: f ?? this.f,
    gain: gain ?? this.gain,
    q: q ?? this.q,
    on: on ?? this.on,
  );

  /// Held to the limits the panel holds it to; a number that is not one is the default.
  EqBand clamped() => EqBand(
    type: type,
    f: _clamp(f.isFinite ? f : 1000, EqLimits.fMin, EqLimits.fMax),
    gain: _clamp(gain.isFinite ? gain : 0, -EqLimits.gainMax, EqLimits.gainMax),
    q: _clamp(
      q.isFinite ? q : 1,
      EqLimits.qMin,
      type.isShelf ? EqLimits.shelfQMax : EqLimits.qMax,
    ),
    on: on,
  );

  /// A new type, as the glass changes it (screen_eq.cpp set_type): a pass starts at Butterworth
  /// rather than turning leftover Q into a resonator, a shelf's Q stops at its cap.
  EqBand withType(EqType to) {
    var nq = q;
    if (to.isPass && !type.isPass) nq = EqLimits.qBw12;
    if (to.isShelf && nq > EqLimits.shelfQMax) nq = EqLimits.shelfQMax;
    return copyWith(type: to, q: nq);
  }

  Map<String, Object> toJson() => {
    'type': type.name,
    'f': f,
    'gain': gain,
    'q': q,
    'on': on,
  };

  /// A band of the API, or null for one the app cannot read.
  static EqBand? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = EqType.values.asNameMap()[json['type']];
    double? number(String k) =>
        json[k] is num ? (json[k] as num).toDouble() : null;
    final f = number('f');
    if (type == null || f == null) return null;
    return EqBand(
      type: type,
      f: f,
      gain: number('gain') ?? 0,
      q: number('q') ?? 1,
      on: json['on'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EqBand &&
      other.type == type &&
      other.f == f &&
      other.gain == gain &&
      other.q == q &&
      other.on == on;

  @override
  int get hashCode => Object.hash(type, f, gain, q, on);

  @override
  String toString() => '${type.name} $f Hz $gain dB Q $q${on ? '' : ' off'}';
}

/// What − and + in a band's sheet step: its frequency, gain or width.
enum EqParam { f, gain, q }

/// JavaScript's Math.round, which the web's and the glass's steps round with: halves go up.
double _round(double x) => (x + 0.5).floorToDouble();

extension EqSteps on EqBand {
  /// A step of [p] in direction [dir] (−1, +1), as the glass's (screen_eq.cpp adjust): a twelfth
  /// of an octave, half a dB, a tenth of Q, a pass's slope along [EqLimits.passQ]. A step on a
  /// band that is off switches it on, as touching its point does.
  EqBand step(EqParam p, int dir) {
    final b = switch (p) {
      EqParam.f => copyWith(
        f: _clamp(
          _round(f * (dir > 0 ? 1.0595 : 1 / 1.0595) * 10) / 10,
          EqLimits.fMin,
          EqLimits.fMax,
        ),
      ),
      EqParam.gain => copyWith(
        gain: _clamp(
          _round((gain + dir * 0.5) * 10) / 10,
          -EqLimits.gainMax,
          EqLimits.gainMax,
        ),
      ),
      EqParam.q when type.isPass => copyWith(
        q: EqLimits
            .passQ[(passQIndex(q) + dir).clamp(0, EqLimits.passQ.length - 1)],
      ),
      EqParam.q => copyWith(
        q: _clamp(
          _round((q + dir * 0.1) * 100) / 100,
          EqLimits.qMin,
          type.isShelf ? EqLimits.shelfQMax : EqLimits.qMax,
        ),
      ),
    };
    return b.copyWith(on: true);
  }

  /// A pass at one of the named alignments says it as a slope (screen_eq.cpp q_text): «LR 12»,
  /// «BW 12»; null for a width.
  String? get alignment {
    if (!type.isPass) return null;
    if ((q - EqLimits.qLr12).abs() < 0.02) return 'LR 12';
    if ((q - EqLimits.qBw12).abs() < 0.02) return 'BW 12';
    return null;
  }
}

/// The place in a pass's slope ladder nearest to [q].
int passQIndex(double q) {
  var best = 0;
  for (var i = 1; i < EqLimits.passQ.length; i++) {
    if ((EqLimits.passQ[i] - q).abs() < (EqLimits.passQ[best] - q).abs()) {
      best = i;
    }
  }
  return best;
}

/// Where a new band goes: in the middle — on the log axis — of the widest stretch no band that is
/// on is in, so its point does not land on another; 1 kHz in an empty set. Two significant figures.
double freeFrequency(List<EqBand> bands) {
  final fs = [
    for (final b in bands)
      if (b.on) b.f,
  ]..sort();
  if (fs.isEmpty) return 1000;
  final edges = [EqLimits.fMin, ...fs, EqLimits.fMax];
  var best = 0.0;
  var at = 1000.0;
  for (var k = 1; k < edges.length; k++) {
    final gap = edges[k] / edges[k - 1];
    if (gap > best) {
      best = gap;
      at = math.sqrt(edges[k] * edges[k - 1]);
    }
  }
  return double.parse(at.toStringAsPrecision(2));
}

/// «+ Додати смугу», for a set shorter than [EqLimits.bands]: a 0 dB peak at a free frequency
/// after the last. The new set and the new band's place, or null when the set has all of them.
({List<EqBand> bands, int i})? addBand(List<EqBand> bands) {
  if (bands.length >= EqLimits.bands) return null;
  final fresh = EqBand(type: EqType.peak, f: freeFrequency(bands));
  return (bands: [...bands, fresh], i: bands.length);
}

/// «Скинути «Власний»»: every band off — what «Рівно» is.
List<EqBand> resetBands(List<EqBand> bands) => [
  for (final b in bands) b.copyWith(on: false),
];

/// The panel moved the EQ document since the revision an edit was made on (409): the edit is not
/// written over its change.
class EqChanged implements Exception {
  const EqChanged();

  @override
  String toString() => 'changed';
}

/// `GET /api/eq`: the document both editors — the glass's EQ page and the app — work on, with a
/// revision that moves on every change (audio_dsp/include/eq_store.h).
class EqDoc {
  const EqDoc({
    required this.rev,
    required this.preset,
    required this.presets,
    this.fs = 48000,
    this.bands = const [],
  });

  final int rev;

  /// The sound that plays, by id; "custom" is «Власний».
  final String preset;

  /// The sounds offered: the eight, and a kept one while it plays (eq_offered).
  final List<String> presets;

  /// The rate the panel plays at, which the curve is drawn for.
  final double fs;

  /// Section 0's, which the panel plays.
  final List<EqBand> bands;

  EqDoc copyWith({int? rev, String? preset, List<EqBand>? bands}) => EqDoc(
    rev: rev ?? this.rev,
    preset: preset ?? this.preset,
    presets: presets,
    fs: fs,
    bands: bands ?? this.bands,
  );

  static EqDoc fromJson(Object? json) {
    final d = json is Map ? json : const {};
    return EqDoc(
      rev: d['rev'] is int ? d['rev'] as int : 0,
      preset: d['preset'] is String ? d['preset'] as String : '',
      presets: [
        for (final p in d['presets'] is List ? d['presets'] as List : const [])
          if (p is String) p,
      ],
      fs: d['fs'] is num && (d['fs'] as num) > 0
          ? (d['fs'] as num).toDouble()
          : 48000,
      bands: [
        for (final b in d['bands'] is List ? d['bands'] as List : const [])
          ?EqBand.fromJson(b),
      ],
    );
  }
}
