/// The EQ curve as the audio core designs it: a port of the firmware's webui/src/lib/eqmath.js,
/// itself a line-for-line port of components/audio_dsp/src/dsp_chain.cpp (design_q, analog_mag2,
/// design_matched, design_svf_params, svf_magnitude_db and eq_curve_db), and of
/// webui/src/lib/syscurve.js, the stages around the EQ.
///
/// A second implementation of the maths for drawing would eventually disagree with what is heard,
/// and nothing would show it. So this one is held to the C++ by the vectors the firmware's host
/// test writes (protocol/eq_curve_vectors.json, a copy of tests/host/fixtures/eq_curve/
/// vectors.json), and the stages to syscurve.js by protocol/eq_cases.json. Everything in double,
/// as the design is.
library;

import 'dart:math' as math;

import 'eq.dart';

/// One band as the audio core runs it: a trapezoidal SVF section (Simper).
class SvfSection {
  const SvfSection(this.g, this.k, this.m0, this.m1, this.m2);

  final double g;
  final double k;
  final double m0;
  final double m1;
  final double m2;
}

double _pow10(double x) => math.pow(10, x).toDouble();

double _log10(double x) => math.log(x) / math.ln10;

double _designQ(EqBand b) =>
    b.type.isShelf && b.q > EqLimits.shelfQMax ? EqLimits.shelfQMax : b.q;

/// |H|² of the band's analogue prototype at [f] — what the matched design aims at.
double analogMag2(EqBand b, double f) {
  final a = _pow10(b.gain / 40);
  final q = _designQ(b);
  final w = f / b.f;
  final w2 = w * w;
  final double nr, ni, dr, di;
  switch (b.type) {
    case EqType.peak:
      nr = 1 - w2;
      ni = (w * a) / q;
      dr = 1 - w2;
      di = w / (a * q);
    case EqType.lowshelf:
      nr = a * (a - w2);
      ni = (a * w * math.sqrt(a)) / q;
      dr = 1 - a * w2;
      di = (w * math.sqrt(a)) / q;
    case EqType.highshelf:
      nr = a * (1 - a * w2);
      ni = (a * w * math.sqrt(a)) / q;
      dr = a - w2;
      di = (w * math.sqrt(a)) / q;
    case EqType.notch:
      nr = 1 - w2;
      ni = 0;
      dr = 1 - w2;
      di = w / q;
    case EqType.lowpass:
      nr = 1;
      ni = 0;
      dr = 1 - w2;
      di = w / q;
    case EqType.highpass:
      nr = -w2;
      ni = 0;
      dr = 1 - w2;
      di = w / q;
  }
  final den = dr * dr + di * di;
  return den > 1e-300 ? (nr * nr + ni * ni) / den : 1;
}

double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

/// Vicanek's matched design for a peak, a shelf or a notch; null where it has no real solution.
SvfSection? _designMatched(EqBand b, double fs) {
  final a = _pow10(b.gain / 40);
  final q = _designQ(b);
  final w0 = (2 * math.pi * b.f) / fs;
  final double wp, zeta;
  switch (b.type) {
    case EqType.peak:
      wp = 1;
      zeta = 1 / (2 * a * q);
    case EqType.lowshelf:
      wp = 1 / math.sqrt(a);
      zeta = 1 / (2 * q);
    case EqType.highshelf:
      wp = math.sqrt(a);
      zeta = 1 / (2 * q);
    case EqType.notch:
      wp = 1;
      zeta = 1 / (2 * q);
    case EqType.lowpass || EqType.highpass:
      return null;
  }
  final wn = w0 * wp;
  final e = math.exp(-zeta * wn);
  final a2 = e * e;
  final a1 = zeta <= 1
      ? -2 * e * math.cos(wn * math.sqrt(1 - zeta * zeta))
      : -2 * e * _cosh(wn * math.sqrt(zeta * zeta - 1));
  final double b0, b1, b2;
  if (b.type == EqType.notch) {
    final cw = math.cos(w0);
    final n = (1 + a1 + a2) / (2 - 2 * cw);
    b0 = n;
    b1 = -2 * n * cw;
    b2 = n;
  } else {
    final aa0 = (1 + a1 + a2) * (1 + a1 + a2);
    final aa1 = (1 - a1 + a2) * (1 - a1 + a2);
    final aa2 = -4 * a2;
    final wm = w0 < 0.9 * math.pi ? w0 : 0.9 * math.pi;
    final p1 = math.sin(wm / 2) * math.sin(wm / 2);
    final p0 = 1 - p1;
    final p2 = 4 * p0 * p1;
    final bb0 = aa0 * analogMag2(b, 0);
    final bb1 = aa1 * analogMag2(b, fs / 2);
    final bb2 =
        (analogMag2(b, (wm * fs) / (2 * math.pi)) *
                (aa0 * p0 + aa1 * p1 + aa2 * p2) -
            bb0 * p0 -
            bb1 * p1) /
        p2;
    final v = (math.sqrt(bb0) + math.sqrt(bb1)) / 2;
    if (v * v + bb2 < 0) return null;
    b1 = (math.sqrt(bb0) - math.sqrt(bb1)) / 2;
    b0 = (v + math.sqrt(v * v + bb2)) / 2;
    b2 = v - b0;
  }
  final dd = 1 - a1 + a2;
  if (!(dd > 0) || !(1 + a1 + a2 > 0)) return null;
  final g = math.sqrt((1 + a1 + a2) / dd);
  if (!(g > 0)) return null;
  final k = (2 * (1 - a2)) / (dd * g);
  final m0 = (b0 - b1 + b2) / dd;
  final m1 = ((2 * (b0 - b2)) / dd - m0 * g * k) / g;
  final m2 = (b0 + b1 + b2) / (dd * g * g) - m0;
  return SvfSection(g, k, m0, m1, m2);
}

/// The band as one SVF section at [fs], or null when it cannot be designed (then it is a wire).
/// [matched] false is the bilinear design, RBJ's own digital filter.
SvfSection? designBand(EqBand b, double fs, {bool matched = true}) {
  if (!(fs >= 1000)) return null;
  final f = b.f;
  final q = _designQ(b);
  if (!(f >= 10) || f > fs * 0.49 || !(q > 0)) return null;
  if (matched) {
    final d = _designMatched(b, fs);
    if (d != null) return d;
  }
  final a = _pow10(b.gain / 40);
  var g = math.tan((math.pi * f) / fs);
  var k = 1 / q;
  final double m0, m1, m2;
  switch (b.type) {
    case EqType.peak:
      k = 1 / (q * a);
      m0 = 1;
      m1 = k * (a * a - 1);
      m2 = 0;
    case EqType.lowshelf:
      g /= math.sqrt(a);
      m0 = 1;
      m1 = k * (a - 1);
      m2 = a * a - 1;
    case EqType.highshelf:
      g *= math.sqrt(a);
      m0 = a * a;
      m1 = k * (1 - a) * a;
      m2 = 1 - a * a;
    case EqType.lowpass:
      m0 = 0;
      m1 = 0;
      m2 = 1;
    case EqType.highpass:
      m0 = 1;
      m1 = -k;
      m2 = -1;
    case EqType.notch:
      m0 = 1;
      m1 = -k;
      m2 = 0;
  }
  return SvfSection(g, k, m0, m1, m2);
}

double _mag2(SvfSection d, double s, double c) {
  final gc = d.g * c;
  final dr = gc * gc - s * s;
  final di = d.k * gc * s;
  final nr = d.m0 * dr + d.m2 * gc * gc;
  final ni = d.m0 * di + d.m1 * gc * s;
  final den = dr * dr + di * di;
  return den > 1e-300 ? (nr * nr + ni * ni) / den : 1;
}

/// |H| of a designed section at [f], in dB.
double svfMagnitudeDb(SvfSection d, double fs, double f) {
  final h = (math.pi * f) / fs;
  final m = _mag2(d, math.sin(h), math.cos(h));
  return m > 1e-30 ? 10 * _log10(m) : -300;
}

/// One band at [f], in dB; a band that is off or cannot be designed is 0 dB.
double bandMagnitudeDb(EqBand b, double fs, double f) {
  if (!b.on) return 0;
  final d = designBand(b, fs);
  return d == null ? 0 : svfMagnitudeDb(d, fs, f);
}

/// The summed curve at each of [freqs], in dB — each band designed once.
List<double> curveDb(List<EqBand> bands, double fs, List<double> freqs) {
  final ds = [
    for (final b in bands)
      if (b.on) ?designBand(b, fs),
  ];
  double at(double f) {
    if (ds.isEmpty) return 0;
    final h = (math.pi * f) / fs;
    final s = math.sin(h);
    final c = math.cos(h);
    var prod = 1.0;
    for (final d in ds) {
      prod *= _mag2(d, s, c);
    }
    return prod > 1e-30 ? 10 * _log10(prod) : -300;
  }

  return [for (final f in freqs) at(f)];
}

// dsp_chain.h
const _toneLoHz = 100.0;
const _toneHiHz = 10000.0;
const _toneQ = 0.71;
const _toneMaxDb = 6.0;
const _loudLoHz = 148.6;
const _loudLoQ = 0.359;
const _loudLoK = 0.5605;
const _loudHiHz = 10000.0;
const _loudHiQ = 0.71;
const _loudHiK = 0.2253;

/// A 4th-order Butterworth as two sections (design_subsonic).
const _subQ = [0.5411961, 1.306563];
const _portQ = 1.4;
const _portSubRatio = 0.8;
const _portLiftMax = 6.0;

/// A stage of the chain around the EQ, as a band; [bilinear] for the loudness's shelves, which the
/// core designs bilinear (shelf_coef).
typedef Stage = ({EqBand band, bool bilinear});

/// «Показати всю систему»: what the stages around the equalizer do to the sound — Бас and Високі,
/// the loudness at the level it is at now, the subsonic and the port's lift — each as the audio
/// core builds it. [bass] and [treble] dB (audio.bass_db, treble_db), [loudDb] the loudness's low
/// shelf now (audio.loud_db), [hpHz] the subsonic asked for (audio.hp_hz), [portHz] and [liftDb]
/// the port that plays (0 for closed speakers).
///
/// Not drawn: what is not a fixed response — the bass limiter and the brickwall act on the level,
/// the width and the mono bass on the stereo image, the balance on one side.
List<Stage> systemStages({
  double bass = 0,
  double treble = 0,
  double loudDb = 0,
  double hpHz = 0,
  double portHz = 0,
  double liftDb = 0,
}) {
  double clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);
  Stage stage(
    EqType type,
    double f,
    double gain,
    double q, {
    bool bilinear = false,
  }) => (band: EqBand(type: type, f: f, gain: gain, q: q), bilinear: bilinear);
  final fc = portHz > 0 ? _portSubRatio * portHz : hpHz;
  return [
    if (fc >= 20 && fc <= 80)
      for (final q in _subQ) stage(EqType.highpass, fc, 0, q),
    if (portHz > 0 && liftDb > 0)
      stage(EqType.peak, portHz, math.min(_portLiftMax, liftDb), _portQ),
    if (loudDb > 0) ...[
      stage(EqType.lowshelf, _loudLoHz, loudDb, _loudLoQ, bilinear: true),
      stage(
        EqType.highshelf,
        _loudHiHz,
        (loudDb * _loudHiK) / _loudLoK,
        _loudHiQ,
        bilinear: true,
      ),
    ],
    if (bass != 0)
      stage(
        EqType.lowshelf,
        _toneLoHz,
        clamp(bass, -_toneMaxDb, _toneMaxDb),
        _toneQ,
      ),
    if (treble != 0)
      stage(
        EqType.highshelf,
        _toneHiHz,
        clamp(treble, -_toneMaxDb, _toneMaxDb),
        _toneQ,
      ),
  ];
}

/// The whole response at each of [freqs], in dB: the equalizer's [bands] (when [eqOn]) and the
/// [stages].
List<double> systemCurveDb(
  List<EqBand> bands,
  List<Stage> stages,
  double fs,
  List<double> freqs, {
  bool eqOn = true,
}) {
  final base = eqOn ? curveDb(bands, fs, freqs) : [for (final _ in freqs) 0.0];
  final ds = [
    for (final s in stages) ?designBand(s.band, fs, matched: !s.bilinear),
  ];
  return [
    for (var i = 0; i < freqs.length; i++)
      ds.fold(base[i], (db, d) => db + svfMagnitudeDb(d, fs, freqs[i])),
  ];
}
