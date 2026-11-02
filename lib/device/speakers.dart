/// Колонки, as the web's lib/speakers.js says them: what the speakers page says the speakers are,
/// what the wizard and the port page write, what the port meter's message means, and «Звичайна
/// гучність»'s reference; and the test tone's keys as the web's lib/calib.js has them. The panel
/// keeps the rules (modules/audio): closed speakers have no port whatever number is kept, the
/// meter only offers what it found, and the reference is a % of the effective level.
/// protocol/speaker_cases.json holds these to what speakers.js says.
library;

import 'keys.dart';

/// audio.spk_type, the manifest's options.
enum SpeakerType {
  unset(0),
  ported(1),
  closed(2);

  const SpeakerType(this.value);

  final int value;

  static SpeakerType of(int? value) =>
      values.firstWhere((t) => t.value == value, orElse: () => unset);
}

/// audio.port_src: where the port frequency came from.
enum PortSource {
  unset(0),
  manual(1),
  measured(3);

  const PortSource(this.value);

  final int value;

  static PortSource of(int? value) =>
      values.firstWhere((s) => s.value == value, orElse: () => unset);
}

/// The speakers page's title: what the speakers are.
enum SpeakerTitle { ported, closed, unset }

/// The line under it, where there is a port to say.
enum PortLine { none, measured, manual, unknown }

/// What a step of the wizard does (the web's names).
enum WizardAction { choose, next, done, accept, skip, keep, stop, retry }

/// The port meter's last word as a state of the wizard.
enum MeterOutcome { idle, running, found, doubtful, failed }

/// JavaScript's Math.round, which the web rounds with: halves go up.
int _round(double x) => (x + 0.5).floor();

/// What the wizard or the port page writes: the type, and for a port its frequency and where it
/// came from.
class SpeakerWrite {
  const SpeakerWrite(this.type, {this.portHz, this.source});

  final SpeakerType type;
  final int? portHz;
  final PortSource? source;

  /// The settings, in the order the web sends them.
  Map<String, Object> get settings => {
    Keys.audioSpkType.name: type.value,
    Keys.audioPortHz.name: ?portHz,
    Keys.audioPortSrc.name: ?source?.value,
  };

  @override
  bool operator ==(Object other) =>
      other is SpeakerWrite &&
      other.type == type &&
      other.portHz == portHz &&
      other.source == source;

  @override
  int get hashCode => Object.hash(type, portHz, source);

  @override
  String toString() => '$settings';
}

/// The speakers as the panel keeps them.
class Speakers {
  const Speakers({
    this.type = SpeakerType.unset,
    this.portHz = 0,
    this.source = PortSource.unset,
  });

  final SpeakerType type;

  /// audio.port_hz as kept: closed speakers keep a number that does not play ([port]).
  final int portHz;
  final PortSource source;

  /// The port the DSP has, and where it came from: none for closed speakers, as read_port() rules.
  ({int hz, bool measured}) get port {
    final hz = type == SpeakerType.closed ? 0 : portHz;
    return (hz: hz, measured: hz > 0 && source == PortSource.measured);
  }

  /// What the speakers page says: the title, then the line with its frequency where there is a
  /// port to say — none where the title says it all, closed or not set up; [again] once the
  /// wizard has been through, so its button says «знову».
  ({SpeakerTitle title, PortLine line, int? hz, bool again}) get summary {
    final p = port;
    if (type == SpeakerType.closed) {
      return (
        title: SpeakerTitle.closed,
        line: PortLine.none,
        hz: null,
        again: true,
      );
    }
    final line = p.hz == 0
        ? PortLine.unknown
        : p.measured
        ? PortLine.measured
        : PortLine.manual;
    if (type == SpeakerType.ported) {
      return (title: SpeakerTitle.ported, line: line, hz: p.hz, again: true);
    }
    // not asked yet: a port somebody set before the wizard existed still plays, so it is said
    return p.hz > 0
        ? (title: SpeakerTitle.unset, line: line, hz: p.hz, again: false)
        : (
            title: SpeakerTitle.unset,
            line: PortLine.none,
            hz: null,
            again: false,
          );
  }
}

/// What a step of the wizard writes, or null for nothing at all. Choosing a type writes nothing;
/// «Пропустити» and «Лишити як було» write nothing; only «Готово» for closed speakers and
/// «Прийняти» for a port found in 30…80 Hz do.
SpeakerWrite? wizardWrite(SpeakerType type, WizardAction action, double hz) {
  if (action == WizardAction.done && type == SpeakerType.closed) {
    return const SpeakerWrite(SpeakerType.closed);
  }
  if (action == WizardAction.accept &&
      type == SpeakerType.ported &&
      hz.isFinite) {
    final f = _round(hz);
    if (f < 30 || f > 80) return null;
    return SpeakerWrite(
      SpeakerType.ported,
      portHz: f,
      source: PortSource.measured,
    );
  }
  return null;
}

/// «Застосувати» on the port page: a measured frequency or one found by hand, held to 30…80 Hz.
SpeakerWrite portWrite(double hz, {required bool measured}) => SpeakerWrite(
  SpeakerType.ported,
  portHz: _round(hz).clamp(30, 80),
  source: measured ? PortSource.measured : PortSource.manual,
);

const _failed = {
  '@cal.m_outside',
  '@cal.m_no_dip',
  '@cal.m_no_tone',
  '@cal.m_mic_open',
  '@cal.m_mic_read',
  '@cal.m_no_memory',
};

/// The port meter's last word (audio.port_meas_status, a "@cal.m_*" message): running while it
/// measures; found, doubtful or failed once it has finished; idle for anything else — not begun,
/// stopped, interrupted.
MeterOutcome meterOutcome(String status, {required bool measuring}) {
  if (measuring) return MeterOutcome.running;
  final key = status.split('\u001f').first;
  if (key == '@cal.m_found') return MeterOutcome.found;
  if (key == '@cal.m_doubtful') return MeterOutcome.doubtful;
  if (_failed.contains(key)) return MeterOutcome.failed;
  return MeterOutcome.idle;
}

/// How far the meter's sweep is, 0…100 %, from its progress message (k of n).
int meterProgress(String status) {
  final m = RegExp('k=(\\d+)\u001fn=(\\d+)').firstMatch(status);
  if (m == null) return 0;
  final n = int.parse(m[2]!);
  return n == 0 ? 0 : _round(100 * int.parse(m[1]!) / n);
}

/// The subsonic under a port: 0.8 of it (DspChain::set_port).
int subUnder(int portHz) => _round(0.8 * portHz);

/// «Звичайна гучність»: the reference for the volume that plays — % of the effective level, which
/// «Максимум» compresses, held to 20…100 as the panel holds it.
int refOf(int volume, [int volMax = 100]) =>
    _round(volume.clamp(0, 100) * volMax / 100).clamp(20, 100);

/// The reference back on the volume's scale, to say it.
int refShown(int ref, [int volMax = 100]) =>
    _round(ref * 100 / (volMax == 0 ? 100 : volMax)).clamp(0, 100);

/// audio.tone_mode: through the DSP and the volume, or past both at an exact DAC level (steady or
/// in 250/750 ms bursts).
enum ToneMode {
  chain(0),
  raw(1),
  bursts(2);

  const ToneMode(this.value);

  final int value;

  static ToneMode of(int? value) =>
      values.firstWhere((m) => m.value == value, orElse: () => chain);
}

/// audio.tone_ch.
enum ToneChannel {
  left(1),
  right(2),
  both(3);

  const ToneChannel(this.value);

  final int value;

  static ToneChannel of(int? value) =>
      values.firstWhere((c) => c.value == value, orElse: () => both);
}

/// The test tone as the panel has it now; a key never written reads its default (calib.js
/// TONE_DEFAULTS: none persists).
class ToneState {
  const ToneState({
    this.on = false,
    this.mode = ToneMode.chain,
    this.hz = 1000,
    this.db10 = -260,
    this.channel = ToneChannel.both,
  });

  /// The source is the tone.
  final bool on;
  final ToneMode mode;
  final int hz;

  /// The level of a calibration tone, tenths of dBFS.
  final int db10;
  final ToneChannel channel;

  /// A calibration tone (mode 1 or 2) turns itself off after this long (TONE_RAW_MAX_MS).
  static const calMax = Duration(seconds: 60);
}
