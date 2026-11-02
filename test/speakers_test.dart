import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/speakers.dart';

/// Колонки against what the firmware's own speakers.js says (protocol/speaker_cases.json,
/// tool/speaker_cases.mjs): a measurement is not written without «Прийняти» or «Застосувати»,
/// a skip or a choice writes nothing, what the page says for each state, the meter's words, the
/// usual volume's scale.
void main() {
  final c = (jsonDecode(
    File('protocol/speaker_cases.json').readAsStringSync(),
  ) as Map).cast<String, Object?>();
  List<Map<String, Object?>> cases(String name) =>
      (c[name]! as List).cast<Map<String, Object?>>();
  Map<String, Object?>? settings(SpeakerWrite? w) => w?.settings;

  test('the wizard writes only on «Готово» for closed speakers and on '
      '«Прийняти» for a port in 30…80 Hz', () {
    for (final x in cases('wizard')) {
      final hz = x['hz'] == null ? double.nan : (x['hz']! as num).toDouble();
      final got = wizardWrite(
        SpeakerType.of(x['type']! as int),
        WizardAction.values.byName(x['action']! as String),
        hz,
      );
      expect(settings(got), x['writes'], reason: '$x');
    }
  });

  test('the port page writes the frequency with where it came from', () {
    for (final x in cases('port')) {
      final got = portWrite(
        (x['hz']! as num).toDouble(),
        measured: x['measured']! as bool,
      );
      expect(settings(got), x['writes'], reason: '$x');
    }
  });

  test('what the speakers page says, and the port that plays', () {
    for (final x in cases('states')) {
      final s = (x['state']! as Map).cast<String, Object?>();
      final speakers = Speakers(
        type: SpeakerType.of(s['audio.spk_type'] as int?),
        portHz: (s['audio.port_hz'] as int?) ?? 0,
        source: PortSource.of(s['audio.port_src'] as int?),
      );
      final p = speakers.port;
      expect({'hz': p.hz, 'measured': p.measured}, x['port'], reason: '$s');
      final got = speakers.summary;
      expect('spk.${got.title.name}', x['title'], reason: '$s');
      expect(
        switch (got.line) {
          PortLine.none => '',
          PortLine.measured => 'spk.port_measured',
          PortLine.manual => 'spk.port_manual',
          PortLine.unknown => 'spk.port_none',
        },
        x['line'],
        reason: '$s',
      );
      expect(got.hz, x['hz'], reason: '$s');
      expect(got.again, x['again'], reason: '$s');
    }
  });

  test('the port meter\'s words', () {
    for (final x in cases('meter')) {
      expect(
        meterOutcome(
          x['status']! as String,
          measuring: x['measuring']! as bool,
        ).name,
        x['outcome'],
        reason: '$x',
      );
    }
    expect(meterProgress('@cal.m_progress\u001fhz=45\u001fk=21\u001fn=41'), 51);
    expect(meterProgress('@cal.m_silence'), 0);
  });

  test('the subsonic under a port, and the usual volume\'s scale', () {
    for (final x in cases('sub')) {
      expect(subUnder(x['hz']! as int), x['sub'], reason: '$x');
    }
    for (final x in cases('ref')) {
      expect(
        refOf(x['volume']! as int, x['volMax']! as int),
        x['ref'],
        reason: '$x',
      );
    }
    for (final x in cases('shown')) {
      expect(
        refShown(x['ref']! as int, x['volMax']! as int),
        x['shown'],
        reason: '$x',
      );
    }
  });

  test('the test tone\'s keys are the web\'s', () {
    final tone = (c['tone']! as Map).cast<String, Object?>();
    expect([for (final m in ToneMode.values) m.value], tone['modes']);
    expect([for (final ch in ToneChannel.values) ch.value], tone['channels']);
    const defaults = ToneState();
    expect({
      'mode': defaults.mode.value,
      'hz': defaults.hz,
      'db10': defaults.db10,
      'ch': defaults.channel.value,
    }, tone['defaults']);
    expect(ToneState.calMax.inSeconds, tone['cal_max_s']);
  });
}
