import 'package:flutter/material.dart';

import '../device/eq.dart';
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

  /// A message the panel publishes — `@key`, then name=value arguments, each behind U+001F —
  /// in the page's language: the web's msg() (webui/src/lib/msg.js). A key the app does not word
  /// — a folder whose name starts with "@" — is shown as it is.
  String message(String raw) {
    final m = _message.firstMatch(raw);
    if (m == null) return raw;
    final key = m[1]!;
    final args = <String, String>{};
    for (final part in raw.substring(1 + key.length).split('\u001f').skip(1)) {
      final eq = part.indexOf('=');
      if (eq > 0) args[part.substring(0, eq)] = part.substring(eq + 1);
    }
    String a(String name) => args[name] ?? '{$name}';
    return switch (key) {
      'app.loading' => appLoading,
      'dlna.servers' => dlnaServers,
      'dlna.searching' => dlnaSearching,
      'dlna.st_servers' => dlnaStServers(a('n')),
      'dlna.st_page' => dlnaStPage(a('n')),
      'dlna.st_no_socket' => dlnaStNoSocket,
      'dlna.st_bad_id' => dlnaStBadId,
      'dlna.st_unreachable' => dlnaStUnreachable,
      'dlna.st_garbled' => dlnaStGarbled,
      'dlna.st_page_size' => dlnaStPageSize,
      'dlna.st_no_total' => dlnaStNoTotal,
      'dlna.st_bad_list' => dlnaStBadList,
      'dlna.st_broken_list' => dlnaStBrokenList,
      'dlna.st_cancelled' => dlnaStCancelled,
      'dlna.st_too_deep' => dlnaStTooDeep,
      'dlna.st_playing' => dlnaStPlaying(a('title')),
      'dlna.st_not_searched' => dlnaStNotSearched,
      'dlna.unsupported' => dlnaUnsupported,
      'dlna.queued' => dlnaQueued(a('title')),
      // switching AirPlay's mode (airplay.mode_status, mode_error)
      'airplay.st_starting' => airplayStStarting,
      'airplay.st_stopped' => airplayStStopped,
      'airplay.st_not_applied' => airplayStNotApplied,
      'airplay.st_switching' => airplayStSwitching,
      'airplay.st_applied' => airplayStApplied,
      'airplay.st_wifi' => airplayStWifi,
      // the port meter (audio.port_meas_status)
      'cal.m_no_memory' => calMNoMemory,
      'cal.m_mic_open' => calMMicOpen,
      'cal.m_silence' => calMSilence,
      'cal.m_stopped' => calMStopped,
      'cal.m_mic_read' => calMMicRead,
      'cal.m_progress' => calMProgress(a('hz'), a('k'), a('n')),
      'cal.m_interrupted' => calMInterrupted,
      'cal.m_found' => calMFound(a('hz')),
      'cal.m_outside' => calMOutside(a('hz')),
      'cal.m_doubtful' => calMDoubtful(a('hz')),
      'cal.m_no_dip' => calMNoDip,
      'cal.m_no_tone' => calMNoTone,
      _ => raw,
    };
  }

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

  /// [x] to [n] decimals with the separator the language writes — a comma but in English — and
  /// the minus sign (U+2212), as the glass's i18n::num and the web's decimal() print it: «1,25 кГц»
  /// and «−3,5 дБ» on all three. A value that rounds to zero has no sign.
  String decimal(double x, int n) {
    var s = x.toStringAsFixed(n);
    if (RegExp(r'^-[0.]+$').hasMatch(s)) s = s.substring(1);
    s = s.replaceFirst('-', '\u2212');
    return localeName == 'en' ? s : s.replaceFirst('.', ',');
  }

  /// A band's type by the names REW and Equalizer APO use, as the glass's list has them.
  String eqTypeName(EqType type) => switch (type) {
    EqType.peak => eqTypePeak,
    EqType.lowshelf => eqTypeLowshelf,
    EqType.highshelf => eqTypeHighshelf,
    EqType.lowpass => eqTypeLowpass,
    EqType.highpass => eqTypeHighpass,
    EqType.notch => eqTypeNotch,
  };

  /// A file's size as the web's firmware page says it: «812 КБ», «1,94 МБ».
  String fileSize(int bytes) => bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(0)} $unitKb'
      : '${decimal(bytes / 1048576, 2)} $unitMb';

  /// «125 Гц», «1,25 кГц».
  String frequency(double f) => f >= 1000
      ? '${decimal(f / 1000, 2)} $unitKhz'
      : '${f.toStringAsFixed(0)} $unitHz';

  /// «+3,5 дБ»; «—» for a type a gain means nothing to.
  String bandGain(EqBand b) => b.type.hasGain
      ? '${b.gain > 0 ? '+' : ''}${decimal(b.gain, 1)} $unitDb'
      : '—';
}

/// The number in [s] as people type it into a field: a decimal comma, "1.2k", the minus the pages
/// print (U+2212) or a dash — the web's parseNumber(). Null for none.
double? parseNumber(String s) {
  final t = s
      .trim()
      .replaceAll(RegExp('[\u2212\u2013]'), '-')
      .replaceFirst(',', '.');
  final m = RegExp(
    r'^([+-]?\d*\.?\d+)\s*(k)?',
    caseSensitive: false,
  ).firstMatch(t);
  if (m == null) return null;
  final v = double.tryParse(m[1]!);
  return v == null ? null : v * (m[2] != null ? 1000 : 1);
}

final _message = RegExp(r'^@([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)(?:\u001f|$)');

/// Where the sound comes from, as an icon: the mini-player's picture.
IconData nowIcon(NowKind kind) => switch (kind) {
  NowKind.bt => Icons.bluetooth,
  NowKind.airplay => Icons.airplay,
  NowKind.radio => Icons.radio,
  NowKind.card => Icons.sd_card,
  NowKind.dlna => Icons.hub,
  NowKind.usb => Icons.usb,
  NowKind.off || NowKind.tone || NowKind.aux => Icons.power_settings_new,
};

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
