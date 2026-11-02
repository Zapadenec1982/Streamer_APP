import 'package:flutter/material.dart';

import '../device/models.dart';
import '../l10n/app_localizations.dart';

/// The words and icons for the models, in the page's language.
extension Words on AppLocalizations {
  String sourceName(SourceId source) => switch (source) {
    SourceId.off => srcOff,
    SourceId.tone => srcTone,
    SourceId.aux => srcAux,
    SourceId.bt => srcBt,
    SourceId.card => srcCard,
    SourceId.radio => srcRadio,
    SourceId.airplay => srcAirplay,
    SourceId.usb => srcUsb,
  };

  String cardName(SourceCard card) =>
      card == SourceCard.servers ? srcServers : sourceName(card.source);

  /// Where the sound comes from, over the Player's cover.
  String kindName(NowKind kind) =>
      kind == NowKind.dlna ? srcDlna : sourceName(kind.source);

  String label(Label label) => switch (label) {
    TextLabel(:final text, technical: true) => badge(text),
    TextLabel(:final text) => text,
    LineLabel(:final line, :final name, :final count) => _line(
      line,
      name ?? '…',
      count ?? 0,
    ),
  };

  String _line(CatalogLine line, String name, int count) => switch (line) {
    CatalogLine.noDevice => nowNoDevice,
    CatalogLine.dlnaTrack => nowDlnaTrack,
    CatalogLine.buffering => nowBuffering,
    CatalogLine.reconnecting => nowReconnecting,
    CatalogLine.stopped => nowStopped,
    CatalogLine.usb => nowUsb,
    CatalogLine.tone => nowTone,
    CatalogLine.aux => nowAux,
    CatalogLine.radio => srcRadio,
    CatalogLine.airplayWaiting => nowAirplayWaiting,
    CatalogLine.airplayPick => nowAirplayPick(name),
    CatalogLine.usbWaiting => nowUsbWaiting,
    CatalogLine.usbPick => nowUsbPick(name),
    CatalogLine.off => nowOff,
    CatalogLine.pick => nowPick,
    CatalogLine.connecting => nowConnecting,
    CatalogLine.phoneOn => srcsubPhoneOn,
    CatalogLine.phoneOff => srcsubPhoneOff,
    CatalogLine.servers => srcsubServers,
    CatalogLine.tracks => srcsubTracks(count),
    CatalogLine.cardNone => srcsubCardNone,
    CatalogLine.stations => srcsubStations(count),
    CatalogLine.radioNone => srcsubRadioNone,
    CatalogLine.airplayWait => srcsubAirplayWait,
    CatalogLine.usbOn => srcsubUsbOn,
    CatalogLine.usbWait => srcsubUsbWait,
  };

  /// A sound by its id (the firmware's eq_presets.cpp), as the web's lib/sounds.js names it; its id
  /// for one this build does not know.
  String soundName(String id) => switch (id) {
    'bass_treble' => eqPresetBassTreble,
    'classical' => eqPresetClassical,
    'club' => eqPresetClub,
    'custom' => eqPresetCustom,
    'dance' => eqPresetDance,
    'electronic' => eqPresetElectronic,
    'flat' => eqPresetFlat,
    'headphones' => eqPresetHeadphones,
    'hiphop' => eqPresetHiphop,
    'jazz' => eqPresetJazz,
    'large_hall' => eqPresetLargeHall,
    'live' => eqPresetLive,
    'loudness' => eqPresetLoudness,
    'more_bass' => eqPresetMoreBass,
    'more_treble' => eqPresetMoreTreble,
    'night' => eqPresetNight,
    'party' => eqPresetParty,
    'pop' => eqPresetPop,
    'reggae' => eqPresetReggae,
    'rock' => eqPresetRock,
    'ska' => eqPresetSka,
    'soft' => eqPresetSoft,
    'soft_rock' => eqPresetSoftRock,
    _ => id,
  };

  /// The panel's colour scheme `ui.theme` by name.
  String schemeName(int scheme) => switch (scheme) {
    1 => sysSchemeBlue,
    2 => sysSchemeGreen,
    3 => sysSchemeRed,
    _ => sysSchemeAmber,
  };

  /// A technical line in the language's units and decimals, as the web's badge() and the
  /// glass's i18n::badge write it: «AAC 44,1 кГц 128 кбіт/с». Two channels go unsaid and a whole
  /// number loses its ",0"; words that are not a number and a unit stay as they are.
  String badge(String raw) {
    final units = {
      'Hz': unitHz,
      'kHz': unitKhz,
      'kbps': unitKbps,
      'bit': unitBit,
    };
    final comma = localeName != 'en';
    final words = raw.split(' ').where((w) => w.isNotEmpty).toList();
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      final unit = i + 1 < words.length ? words[i + 1] : null;
      final number = RegExp(r'^(\d+/)?(\d+)(?:\.(\d+))?$').firstMatch(words[i]);
      if (unit == 'ch' &&
          number != null &&
          number[1] == null &&
          number[2] == '2') {
        i++;
        continue;
      }
      if (number == null || !units.containsKey(unit)) {
        out.add(words[i]);
        continue;
      }
      final fraction = number[3] ?? '';
      final decimals = RegExp('[1-9]').hasMatch(fraction)
          ? (comma ? ',' : '.') + fraction
          : '';
      out
        ..add('${number[1] ?? ''}${number[2]}$decimals')
        ..add(units[unit]!);
      i++;
    }
    return out.join(' ');
  }
}

IconData cardIcon(SourceCard card) => switch (card) {
  SourceCard.bt => Icons.bluetooth,
  SourceCard.airplay => Icons.airplay,
  SourceCard.radio => Icons.radio,
  SourceCard.card => Icons.sd_card,
  SourceCard.servers => Icons.hub,
  SourceCard.usb => Icons.usb,
};

/// m:ss, or h:mm:ss past an hour.
String clock(Duration d) {
  final s = d.inSeconds;
  final mmss = '${(s ~/ 60) % 60}:${(s % 60).toString().padLeft(2, '0')}';
  return s >= 3600 ? '${s ~/ 3600}:${mmss.padLeft(5, '0')}' : mmss;
}
