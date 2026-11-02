// speaker_cases.mjs — Колонки, from the firmware's own webui/src/lib/speakers.js, for
// protocol/speaker_cases.json: the cases the app's Dart port (lib/device/speakers.dart) is tested
// on — the wizard's writes, the port page's, what the speakers page says, the port meter's words,
// the subsonic under a port and «Звичайна гучність»'s scale. The inputs are the web's own test
// cases (tools/tests/test_webui_speakers.py) and a few more; the answers are what speakers.js
// says. MODESP_PLAYER_ROOT names the firmware checkout (default ../modesp-player).
//
//   node tool/speaker_cases.mjs           # rewrite protocol/speaker_cases.json
//   node tool/speaker_cases.mjs --check   # exit 1 if it differs from what the web says
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fw = resolve(process.env.MODESP_PLAYER_ROOT || resolve(root, '..', 'modesp-player'));
const sp = await import(pathToFileURL(resolve(fw, 'webui/src/lib/speakers.js')).href);
const calib = await import(pathToFileURL(resolve(fw, 'webui/src/lib/calib.js')).href);

const ACTIONS = ['choose', 'next', 'done', 'accept', 'skip', 'keep', 'stop', 'retry'];
const wizard = [];
for (const type of [sp.SPK_UNSET, sp.SPK_PORTED, sp.SPK_CLOSED]) {
  for (const action of ACTIONS) {
    for (const hz of [62.4, 62.5, 29.4, 29.5, 80.4, 80.5, 25, 95, null]) {
      wizard.push({ type, action, hz, writes: sp.wizardWrites(type, action, hz === null ? NaN : hz) });
    }
  }
}

const port = [];
for (const hz of [62.6, 45, 44.5, 20, 120, 30, 80]) {
  for (const measured of [true, false]) port.push({ hz, measured, writes: sp.portWrites(hz, measured) });
}

const states = [
  {},
  { 'audio.port_hz': 62, 'audio.port_src': 1 },
  { 'audio.port_hz': 62, 'audio.port_src': 3 },
  { 'audio.spk_type': 1, 'audio.port_hz': 62, 'audio.port_src': 3 },
  { 'audio.spk_type': 1, 'audio.port_hz': 55, 'audio.port_src': 1 },
  { 'audio.spk_type': 1, 'audio.port_hz': 55, 'audio.port_src': 0 },
  { 'audio.spk_type': 1 },
  { 'audio.spk_type': 2, 'audio.port_hz': 62, 'audio.port_src': 3 },
  { 'audio.spk_type': 2 },
].map((s) => {
  const st = sp.speakerState(s);
  return { state: s, port: sp.port(s), title: st.title, line: st.line, hz: st.args.hz ?? null, again: st.again };
});

const U = '\x1f';
const meter = [];
for (const status of ['', '@cal.m_progress' + U + 'hz=45' + U + 'k=21' + U + 'n=41', '@cal.m_found' + U + 'hz=62',
  '@cal.m_doubtful' + U + 'hz=62', '@cal.m_outside' + U + 'hz=95', '@cal.m_no_dip', '@cal.m_no_tone',
  '@cal.m_mic_open', '@cal.m_mic_read', '@cal.m_no_memory', '@cal.m_stopped', '@cal.m_interrupted',
  '@cal.m_silence']) {
  for (const measuring of [true, false]) meter.push({ status, measuring, outcome: sp.meterOutcome(status, measuring) });
}

const sub = [30, 45, 62, 63, 80].map((hz) => ({ hz, sub: sp.subUnder(hz) }));
const ref = [];
for (const [v, max] of [[42, 100], [50, 85], [10, 100], [100, 100], [0, 40], [100, 40], [77, 55]]) {
  ref.push({ volume: v, volMax: max, ref: sp.refOf(v, max) });
}
const shown = [];
for (const [r, max] of [[43, 85], [42, 100], [20, 40], [100, 40], [100, 100], [55, 55]]) {
  shown.push({ ref: r, volMax: max, shown: sp.refShown(r, max) });
}

const out = {
  _comment: 'Written by tool/speaker_cases.mjs from the firmware\'s speakers.js and calib.js - do not edit by hand.',
  tone: { modes: [calib.CHAIN, calib.RAW, calib.BURSTS], channels: [calib.LEFT, calib.RIGHT, calib.BOTH],
    defaults: calib.TONE_DEFAULTS, cal_max_s: calib.CAL_MAX_S },
  wizard, port, states, meter, sub, ref, shown,
};
const path = resolve(root, 'protocol', 'speaker_cases.json');
const text = JSON.stringify(out, null, 1) + '\n';
if (process.argv.includes('--check')) {
  let current = '';
  try { current = readFileSync(path, 'utf8'); } catch { /* none yet */ }
  if (current !== text) {
    console.log('protocol/speaker_cases.json differs from speakers.js: run node tool/speaker_cases.mjs');
    process.exit(1);
  }
} else {
  writeFileSync(path, text);
  console.log(`wrote protocol/speaker_cases.json (${wizard.length} wizard steps, ${states.length} states)`);
}
