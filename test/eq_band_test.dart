import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/eq.dart';
import 'package:streamer/l10n/app_localizations.dart';
import 'package:streamer/ui/labels.dart';

/// A band in its sheet as the web's dsp/BandSheet.svelte and the glass's screen_eq.cpp step it and
/// say it.
void main() {
  const peak = EqBand(type: EqType.peak, f: 1000, gain: 0, q: 1);

  test('− and + step a twelfth of an octave, half a dB, a tenth of Q', () {
    expect(peak.step(EqParam.f, 1).f, 1059.5);
    expect(peak.step(EqParam.f, -1).f, 943.8);
    expect(peak.copyWith(f: 19000).step(EqParam.f, 1).f, 20000);
    expect(peak.copyWith(f: 20).step(EqParam.f, -1).f, 20);
    expect(peak.copyWith(gain: 11.8).step(EqParam.gain, 1).gain, 12);
    // halves go up, as JavaScript's Math.round has it
    expect(peak.copyWith(gain: -0.75).step(EqParam.gain, 1).gain, -0.2);
    expect(peak.step(EqParam.q, 1).q, 1.1);
    expect(peak.copyWith(q: 0.3).step(EqParam.q, -1).q, 0.3);
    const shelf = EqBand(type: EqType.lowshelf, f: 100, gain: 3, q: 0.95);
    expect(shelf.step(EqParam.q, 1).q, 1, reason: 'a shelf stops at 1');
  });

  test(
    'a pass\'s slope walks its ladder; the named ones are said as slopes',
    () {
      const pass = EqBand(type: EqType.highpass, f: 40, q: 0.707);
      expect(pass.step(EqParam.q, 1).q, 0.8);
      expect(pass.step(EqParam.q, -1).q, 0.6);
      expect(pass.copyWith(q: 8).step(EqParam.q, 1).q, 8);
      expect(pass.alignment, 'BW 12');
      expect(pass.copyWith(q: 0.5).alignment, 'LR 12');
      expect(pass.copyWith(q: 0.6).alignment, isNull);
      expect(peak.copyWith(q: 0.707).alignment, isNull);
    },
  );

  test('a step on a band that is off switches it on', () {
    final off = peak.copyWith(on: false);
    for (final p in EqParam.values) {
      expect(off.step(p, 1).on, isTrue, reason: '$p');
    }
  });

  test('numbers are said as the glass says them, and read as people type '
      'them', () {
    final uk = lookupAppLocalizations(const Locale('uk'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(uk.decimal(1.25, 2), '1,25');
    expect(en.decimal(1.25, 2), '1.25');
    expect(uk.decimal(-3.5, 1), '−3,5');
    expect(uk.decimal(-0.04, 1), '0,0', reason: 'no sign on a zero');
    expect(uk.frequency(62.5), '63 Гц');
    expect(uk.frequency(1250), '1,25 кГц');
    expect(uk.bandGain(peak.copyWith(gain: 3.5)), '+3,5 дБ');
    expect(uk.bandGain(peak.copyWith(gain: -2)), '−2,0 дБ');
    expect(uk.bandGain(peak.copyWith(type: EqType.lowpass)), '—');
    expect(parseNumber('1.2k'), 1200);
    expect(parseNumber('1,5'), 1.5);
    expect(parseNumber('−3'), -3);
    expect(parseNumber('–3'), -3);
    expect(parseNumber(' 250 Гц'), 250);
    expect(parseNumber('+2'), 2);
    expect(parseNumber('.5'), 0.5);
    expect(parseNumber('abc'), isNull);
  });
}
