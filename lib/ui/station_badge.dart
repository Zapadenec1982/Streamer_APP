import 'dart:convert';

/// A station's stand-in for a logo: a disc in a colour of its own with a short label — the glass's
/// rule (the firmware's modules/ui_lvgl/include/station_badge.h), ported from the web's copy
/// (webui/src/lib/stationbadge.js) so the app draws the same disc in the same colour for the same
/// name. protocol/station_badges.json, computed by that JavaScript, holds this port to it.
///
/// The colour: FNV-1a over the name's UTF-8 bytes, over eight muted hues white reads on. The label:
/// the first word that says something — numbers and the word "radio" skipped — when it has at most
/// five characters, otherwise the initials of the name's words, at most three.
class StationBadge {
  const StationBadge({
    required this.label,
    required this.first,
    required this.color,
  });

  /// Up to five characters; empty for a name without a letter or a digit.
  final String label;

  /// The label's first character, for the presets.
  final String first;

  /// 0xRRGGBB.
  final int color;

  static const palette = [
    0x9D5252,
    0x8F5C38,
    0x74682E,
    0x467342,
    0x18746B,
    0x006F9E,
    0x63629B,
    0x92537C,
  ];

  static const _labelMax = 5;
  static const _initials = 3;
  static const _words = 32;

  factory StationBadge.of(String? name) {
    final text = name ?? '';
    final color = palette[_fnv1a(text) % palette.length];
    final words = <({List<int> cps, bool letter})>[];
    List<int>? cps;
    var letter = false;
    void close() {
      if (cps != null) words.add((cps: cps!, letter: letter));
      cps = null;
      letter = false;
    }

    for (final cp in text.runes) {
      if (!_isLetter(cp) && !_isDigit(cp)) {
        close();
        continue;
      }
      if (cps == null) {
        if (words.length >= _words) break;
        cps = [];
      }
      cps!.add(cp);
      letter = letter || _isLetter(cp);
    }
    close();

    // the word that names the station: the first with a letter that is not "radio"; else the
    // first with a letter ("Radio 1"); else the first ("538")
    var key = words.indexWhere((w) => w.letter && !_isRadio(w.cps));
    if (key < 0) key = words.indexWhere((w) => w.letter);
    if (key < 0 && words.isNotEmpty) key = 0;
    var label = '';
    if (key >= 0 && words[key].cps.length <= _labelMax) {
      label = _caps(words[key].cps);
    } else if (key >= 0) {
      label = _caps([
        for (final w in words.where((w) => w.letter).take(_initials))
          w.cps.first,
      ]);
    }
    final first = label.isEmpty ? '' : String.fromCharCode(label.runes.first);
    return StationBadge(label: label, first: first, color: color);
  }

  static int _fnv1a(String text) {
    var h = 2166136261;
    for (final b in utf8.encode(text)) {
      h = ((h ^ b) * 16777619) & 0xFFFFFFFF;
    }
    return h;
  }

  static bool _isDigit(int cp) => cp >= 0x30 && cp <= 0x39;

  /// A letter of a name: Latin, accented Latin, Cyrillic and the other alphabets.
  static bool _isLetter(int cp) {
    if (cp < 0x80) return (cp | 0x20) >= 0x61 && (cp | 0x20) <= 0x7A;
    if (cp < 0xC0 || cp == 0xD7 || cp == 0xF7) return false;
    if (cp >= 0x2000 && cp <= 0x2BFF) return false;
    if (cp >= 0x3000 && cp <= 0x303F) return false;
    if (cp >= 0xFE00 && cp <= 0xFE0F) return false;
    return cp != 0xFFFD && cp < 0x1F000;
  }

  /// The capital of [cp] in the scripts the glass draws; anything else as it is.
  static int upper(int cp) {
    if (cp >= 0x61 && cp <= 0x7A) return cp - 0x20;
    if (cp >= 0xE0 && cp <= 0xFE && cp != 0xF7) return cp - 0x20;
    if (cp == 0xFF) return 0x178;
    if (cp >= 0x100 && cp <= 0x17F) {
      if (cp == 0x131) return 0x49;
      if (cp == 0x17F) return 0x53;
      if (cp == 0x138 || cp == 0x149) return cp;
      final capitalOdd =
          (cp >= 0x139 && cp <= 0x148) || (cp >= 0x179 && cp <= 0x17E);
      return cp % 2 == (capitalOdd ? 0 : 1) ? cp - 1 : cp;
    }
    if (cp == 0x219 || cp == 0x21B) return cp - 1;
    if (cp >= 0x430 && cp <= 0x44F) return cp - 0x20;
    if (cp >= 0x450 && cp <= 0x45F) return cp - 0x50;
    if (cp == 0x491) return 0x490;
    return cp;
  }

  static const _radio = [
    [0x52, 0x41, 0x44, 0x49, 0x4F],
    [0x52, 0xC1, 0x44, 0x49, 0x4F],
    [0x420, 0x410, 0x414, 0x406, 0x41E],
    [0x420, 0x410, 0x414, 0x418, 0x41E],
  ];

  static bool _isRadio(List<int> cps) =>
      cps.length == 5 &&
      _radio.any(
        (r) =>
            [for (var i = 0; i < 5; i++) upper(cps[i]) == r[i]].every((x) => x),
      );

  static String _caps(List<int> cps) => String.fromCharCodes(cps.map(upper));
}
