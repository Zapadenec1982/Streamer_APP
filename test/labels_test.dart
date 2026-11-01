import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/models.dart';
import 'package:streamer/l10n/app_localizations.dart';
import 'package:streamer/ui/labels.dart';

void main() {
  final uk = lookupAppLocalizations(const Locale('uk'));
  final en = lookupAppLocalizations(const Locale('en'));

  test(
    'the codec badge speaks the language, as the web and the glass write it',
    () {
      expect(uk.badge('LHDC V5 96.0 kHz'), 'LHDC V5 96 кГц');
      expect(uk.badge('AAC 44.1 kHz 2 ch 128 kbps'), 'AAC 44,1 кГц 128 кбіт/с');
      expect(en.badge('AAC 44.1 kHz 2 ch 128 kbps'), 'AAC 44.1 kHz 128 kbit/s');
      expect(uk.badge('FLAC 44.1 kHz 16 bit'), 'FLAC 44,1 кГц 16 біт');
      expect(uk.badge('16/44.1 kHz'), '16/44,1 кГц');
      expect(uk.badge(''), '');
    },
  );

  test('catalog lines take the plural and the panel name', () {
    expect(
      uk.label(const LineLabel(CatalogLine.stations, count: 1)),
      'У списку 1 станція',
    );
    expect(
      uk.label(const LineLabel(CatalogLine.stations, count: 3)),
      'У списку 3 станції',
    );
    expect(
      uk.label(const LineLabel(CatalogLine.stations, count: 12)),
      'У списку 12 станцій',
    );
    expect(
      en.label(const LineLabel(CatalogLine.airplayPick, name: 'ModESP')),
      'Choose “ModESP” on your phone',
    );
    expect(uk.label(const TextLabel('Radio Lantern')), 'Radio Lantern');
  });

  test('every source and card has a name', () {
    for (final l in [uk, en]) {
      for (final s in SourceId.values) {
        expect(l.sourceName(s), isNotEmpty);
      }
      for (final c in SourceCard.values) {
        expect(l.cardName(c), isNotEmpty);
      }
    }
  });

  test('clock', () {
    expect(clock(const Duration(seconds: 56)), '0:56');
    expect(clock(const Duration(minutes: 3, seconds: 1)), '3:01');
    expect(clock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
}
