/// What plays, one shape for every source: a port of `face()` in the firmware's
/// webui/src/stores/now.js, which draws the same faces as the glass (screen_now.cpp). It is held to
/// now.js by protocol/now_faces.json, whose faces now.js itself computes (tool/now_faces.mjs).
///
/// Transport is not here: every source's buttons are `audio.transport`, and which of them a source
/// takes is the panel's `audio.transport_caps`.
library;

/// The face of the source that plays. Text is the panel's own ([title], [subtitle]) or a catalog
/// key ([titleKey], [subtitleKey]) when the panel has none.
class Face {
  const Face({
    required this.kind,
    required this.source,
    required this.icon,
    required this.nameKey,
    this.fromKey,
    this.device = '',
    this.title,
    this.titleKey,
    this.subtitle,
    this.subtitleKey,
    this.subtitleArgs,
    this.format = '',
    this.playing = false,
    this.live = false,
    this.progress,
    this.pos = 0,
    this.dur = 0,
    this.seekKey,
    this.repeat,
    this.shuffle,
  });

  /// off | tone | aux | bt | card | radio | dlna | airplay | usb
  final String kind;

  /// The `audio.source` of this face; DLNA rides the radio's 5.
  final int source;

  /// A Material Symbols name.
  final String icon;
  final String nameKey;

  /// The catalog key of the line over the cover — the source's name — or null where the sound is
  /// not played from anywhere (the tone, AUX, off).
  final String? fromKey;

  /// The phone or computer it plays from, or ''.
  final String device;
  final String? title;
  final String? titleKey;
  final String? subtitle;
  final String? subtitleKey;
  final Map<String, String>? subtitleArgs;

  /// The codec badge as the panel writes it, or ''.
  final String format;
  final bool playing;

  /// The transport has someone to command (Bluetooth needs a phone; AirPlay needs the sender's
  /// remote).
  final bool live;

  /// 'track' when [pos] and [dur] mean something, else null.
  final String? progress;
  final num pos;
  final num dur;
  final String? seekKey;
  final int? repeat;
  final bool? shuffle;

  /// The fields as now_faces.json writes them.
  Map<String, Object?> toJson() => {
    'kind': kind,
    'source': source,
    'icon': icon,
    'nameKey': nameKey,
    'fromKey': fromKey,
    'device': device,
    'title': title,
    'titleKey': titleKey,
    'subtitle': subtitle,
    'subtitleKey': subtitleKey,
    'subtitleArgs': subtitleArgs,
    'format': format,
    'playing': playing,
    'live': live,
    'progress': progress,
    'pos': pos,
    'dur': dur,
    'seekKey': seekKey,
    'repeat': repeat,
    'shuffle': shuffle,
  };
}

/// JavaScript's truthiness, which now.js leans on throughout.
bool _truthy(Object? v) =>
    v != null && v != false && v != '' && !(v is num && (v == 0 || v.isNaN));

/// `a || b`.
Object? _or(Object? a, Object? b) => _truthy(a) ? a : b;

/// A number as a JavaScript template string writes it: 1000, not 1000.0.
String _js(Object? v) =>
    v is double && v == v.truncateToDouble() ? v.toInt().toString() : '$v';

String? _str(Object? v) => v?.toString();

num _num(Object? v) => _truthy(v) && v is num ? v : 0;

String _join(List<Object?> parts) => parts.where(_truthy).join(' — ');

String _base(Object? path) => _truthy(path)
    ? path.toString().split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), '')
    : '';

/// The panel drops " 2 ch" from the format chip (screen_now.cpp).
String _compact(Object? f) =>
    _truthy(f) ? f.toString().replaceFirst(' 2 ch', '') : '';

Face face(Map<String, Object?> s) {
  final src = s['audio.source'];
  final radioState = _or(s['radio.state'], 'idle');

  if (src == 4) {
    final count = _or(s['player.count'], 0);
    final index = _or(s['player.index'], 0) as num;
    return Face(
      kind: 'card',
      source: 4,
      icon: 'sd_card',
      nameKey: 'src.card',
      fromKey: 'src.card',
      title: _str(_or(_or(s['player.title'], _base(s['player.track'])), '—')),
      subtitle: _str(
        _or(
          _join([s['player.artist'], s['player.album']]),
          _truthy(count) ? '${_js(index + 1)} / ${_js(count)}' : '',
        ),
      ),
      format: _compact(s['player.format']),
      playing: s['player.state'] == 'playing',
      live: true,
      progress: 'track',
      pos: _num(s['player.pos_s']),
      dur: _num(s['player.dur_s']),
      seekKey: 'player.seek_s',
      repeat: (_or(s['player.repeat'], 0) as num).toInt(),
      shuffle: _truthy(s['player.shuffle']),
    );
  }

  if (src == 5 && s['radio.mode'] == 'push') {
    final own = _truthy(s['radio.url']) && s['radio.url'] == s['dlna.uri']
        ? s['dlna.title']
        : '';
    final title = _str(_or(_or(own, s['radio.now_playing']), null));
    return Face(
      kind: 'dlna',
      source: 5,
      icon: 'cast',
      nameKey: 'src.dlna',
      fromKey: 'src.dlna',
      title: title,
      titleKey: _truthy(title) ? null : 'now.dlna_track',
      subtitle: _join([s['dlna.artist'], s['dlna.album']]),
      format: _compact(s['radio.format']),
      playing: s['dlna.state'] == 'PLAYING',
      live: true,
      progress: 'track',
      pos: _num(s['radio.pos_s']),
      dur: _num(s['radio.dur_s']),
      seekKey: _truthy(s['radio.seekable']) ? 'radio.seek_s' : null,
    );
  }

  if (src == 5) {
    // The station face: who plays — the station — and under it what, the ICY title once it plays,
    // the state in words until then. No progress.
    const sounding = ['playing', 'buffering', 'connecting', 'reconnecting'];
    final name = s['radio.name'];
    final stateKey =
        const {
          'connecting': 'now.connecting',
          'buffering': 'now.buffering',
          'reconnecting': 'now.reconnecting',
        }[radioState] ??
        (radioState == 'playing' ? null : 'now.stopped');
    return Face(
      kind: 'radio',
      source: 5,
      icon: 'radio',
      nameKey: 'src.radio',
      fromKey: 'src.radio',
      title: _truthy(name) ? '$name' : null,
      titleKey: _truthy(name) ? null : 'src.radio',
      subtitle: radioState == 'playing'
          ? _str(_or(s['radio.now_playing'], null))
          : null,
      subtitleKey: stateKey,
      format: _compact(s['radio.format']),
      playing: sounding.contains(radioState),
      live: true,
    );
  }

  if (src == 3) {
    final phone = _truthy(s['bt.peer']);
    final rate = _truthy(s['bt.rate_hz'])
        ? ' ${((s['bt.rate_hz'] as num) / 1000).toStringAsFixed(1)} kHz'
        : '';
    return Face(
      kind: 'bt',
      source: 3,
      icon: 'bluetooth',
      nameKey: 'src.bt',
      fromKey: 'src.bt',
      device: _str(_or(s['bt.peer'], '')) ?? '',
      // no phone: «Телефон не підключено», once — not «Немає пристрою» over «телефон не підключено»
      title: _str(_or(s['bt.title'], phone ? 'Bluetooth' : null)),
      titleKey: _truthy(s['bt.title']) || phone ? null : 'now.no_device',
      subtitle: _str(_or(_join([s['bt.artist'], s['bt.album']]), null)),
      format: _truthy(s['bt.codec']) ? '${s['bt.codec']}$rate' : '',
      playing: s['bt.play_state'] == 'playing',
      live: phone,
      progress: 'track',
      pos: _num(s['bt.pos_s']),
      dur: _num(s['bt.dur_s']),
    );
  }

  if (src == 6) {
    final active = const [
      'connected',
      'playing',
      'paused',
    ].contains(s['airplay.state']);
    return Face(
      kind: 'airplay',
      source: 6,
      icon: 'airplay',
      nameKey: 'src.airplay',
      fromKey: 'src.airplay',
      title: _str(_or(s['airplay.title'], active ? 'AirPlay' : null)),
      titleKey: _truthy(s['airplay.title']) || active
          ? null
          : 'now.airplay_waiting',
      subtitle: _str(
        _or(_join([s['airplay.artist'], s['airplay.album']]), null),
      ),
      subtitleKey: active ? null : 'now.airplay_pick',
      subtitleArgs: {'name': _str(_or(s['airplay.name'], '…'))!},
      format: 'AirPlay',
      playing: s['airplay.state'] == 'playing',
      live: _truthy(s['airplay.remote']),
      progress: 'track',
      pos: _num(s['airplay.pos_s']),
      dur: _num(s['airplay.dur_s']),
    );
  }

  if (src == 1) {
    return Face(
      kind: 'tone',
      source: 1,
      icon: 'graphic_eq',
      nameKey: 'src.tone',
      titleKey: 'now.tone',
      subtitle: _truthy(s['audio.tone_hz'])
          ? '${_js(s['audio.tone_hz'])} Hz'
          : '',
      playing: true,
    );
  }
  if (src == 2) {
    return const Face(
      kind: 'aux',
      source: 2,
      icon: 'input',
      nameKey: 'src.aux',
      titleKey: 'now.aux',
      subtitle: '',
      playing: true,
    );
  }
  if (src == 7) {
    // A computer, over USB: no track and no transport — the computer is its own remote.
    final st = s['usb_audio.state'];
    final streaming = st == 'playing';
    final rate = s['usb_audio.rate'];
    final line = streaming && _truthy(rate)
        ? '${((rate as num) / 1000).toStringAsFixed(1)} kHz ${_truthy(s['usb_audio.bits']) ? _js(s['usb_audio.bits']) : ''} bit'
        : '';
    return Face(
      kind: 'usb',
      source: 7,
      icon: 'usb',
      nameKey: 'src.usb',
      fromKey: 'src.usb',
      titleKey: streaming || st == 'ready' ? 'now.usb' : 'now.usb_waiting',
      subtitle: line.isNotEmpty ? line : null,
      subtitleKey: line.isNotEmpty ? null : 'now.usb_pick',
      subtitleArgs: {'name': _str(_or(s['usb_audio.name'], '…'))!},
      playing: streaming,
    );
  }
  return const Face(
    kind: 'off',
    source: 0,
    icon: 'power_settings_new',
    nameKey: 'src.off',
    titleKey: 'now.off',
    subtitleKey: 'now.pick',
  );
}
