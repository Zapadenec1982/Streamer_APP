// eq_cases.mjs — the EQ edits and the whole system's curve, from the firmware's own
// webui/src/lib/eqband.js and syscurve.js, for protocol/eq_cases.json: the cases the app's Dart
// ports (lib/device/eq.dart, lib/device/eq_math.dart) are tested on. The curve of the EQ alone is
// the firmware's vectors (protocol/eq_curve_vectors.json, tool/sync_eq_vectors.py); these are the
// rest of what the web computes about a set of bands.
//
// The inputs are written here by hand; the answers are what the web's libraries say for them.
// MODESP_PLAYER_ROOT names the firmware checkout (default ../modesp-player).
//
//   node tool/eq_cases.mjs           # rewrite protocol/eq_cases.json
//   node tool/eq_cases.mjs --check   # exit 1 if it differs from what the web says
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fw = resolve(process.env.MODESP_PLAYER_ROOT || resolve(root, '..', 'modesp-player'));
const lib = (name) => import(pathToFileURL(resolve(fw, 'webui/src/lib', name)).href);
const { clampBand, withType, passQIndex, freeFrequency, addBand } = await lib('eqband.js');
const { systemBands, systemCurveDb } = await lib('syscurve.js');

const band = (type, f, gain, q, on = true) => ({ type, f, gain, q, on });
const PRESET_F = [40, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 12000];
const preset = (gains) => gains.map((g, i) =>
  band(i === 0 ? 'lowshelf' : i === 9 ? 'highshelf' : 'peak', PRESET_F[i], g, i === 0 || i === 9 ? 0.707 : 1, Math.abs(g) >= 0.05));
const ROCK = preset([4.9, 3.6, 3.1, -0.8, -4.2, -1.8, 0.7, 2.5, 4.5, 7.0]);
const CLASSICAL = preset([0, 0, 0, -0.1, -0.2, 0, 0.7, -1.0, -3.5, -5.5]);
// a third of an octave from 20 Hz to 20 kHz, as the plot samples it more finely
const FREQS = Array.from({ length: 31 }, (_, i) => Number((20 * Math.pow(10, (i * 3) / 30)).toPrecision(6)));

const sets = {
  empty: [],
  one: [band('peak', 1000, 3, 1)],
  rock: ROCK,
  classical: CLASSICAL,
  low_end: [band('lowshelf', 20, 6, 0.7), band('peak', 25, -3, 2)],
  some_off: [band('peak', 100, 3, 1), band('peak', 1000, 3, 1, false), band('highpass', 30, 0, 0.707)],
  nine: ROCK.slice(0, 9),
};

const free = Object.entries(sets).map(([name, bands]) => {
  const added = addBand(bands);
  return { name, bands, free: freeFrequency(bands), added: added && { i: added.i, band: added.bands[added.i] } };
});

const clamp = [
  band('peak', 5, 20, 10),
  band('peak', 30000, -20, 0.1),
  band('lowshelf', 1000, 3, 4),
  band('highshelf', 8000, -3, 0.2),
  band('notch', 15000, 0, 9),
  band('lowpass', 19999.5, 12.5, 0.3, false),
].map((b) => ({ band: b, clamped: clampBand(b) }));

const TYPES = ['peak', 'lowshelf', 'highshelf', 'lowpass', 'highpass', 'notch'];
const retype = [];
for (const from of [band('peak', 500, 3, 4), band('lowpass', 8000, 0, 0.5), band('notch', 60, 0, 0.8)]) {
  for (const to of TYPES) retype.push({ band: from, to, out: withType(from, to) });
}

const passQ = [0.1, 0.3, 0.45, 0.5, 0.55, 0.65, 0.707, 0.75, 1.15, 2.2, 7, 9].map((q) => ({ q, i: passQIndex(q) }));

// the stages as the EQ page asks for them (DspPage.svelte): Бас and Високі, the loudness now, the
// subsonic asked for, the port that plays and its lift
const stages = [
  { name: 'defaults', fs: 48000, eq: 'rock', eqOn: true, s: { bass: 0, treble: 0, loudDb: 0, hpHz: 40, portHz: 0, liftDb: 3 } },
  { name: 'everything', fs: 48000, eq: 'rock', eqOn: true, s: { bass: 4, treble: -3, loudDb: 6.5, hpHz: 40, portHz: 45, liftDb: 3 } },
  { name: 'tone_only', fs: 44100, eq: 'empty', eqOn: true, s: { bass: 6, treble: 0, loudDb: 0, hpHz: 0, portHz: 0, liftDb: 3 } },
  { name: 'eq_off', fs: 48000, eq: 'classical', eqOn: false, s: { bass: 0, treble: 6, loudDb: 12.3, hpHz: 80, portHz: 0, liftDb: 0 } },
  { name: 'held_to_limits', fs: 96000, eq: 'one', eqOn: true, s: { bass: 7, treble: -8, loudDb: 0, hpHz: 40, portHz: 60, liftDb: 6.5 } },
  { name: 'port_low', fs: 48000, eq: 'low_end', eqOn: true, s: { bass: -2, treble: 2, loudDb: 0.4, hpHz: 60, portHz: 30, liftDb: 2 } },
  { name: 'subsonic_out_of_range', fs: 48000, eq: 'some_off', eqOn: true, s: { bass: 0, treble: 0, loudDb: 0, hpHz: 15, portHz: 0, liftDb: 3 } },
].map((c) => {
  const bands = systemBands(c.s);
  return { ...c, stages: bands, curve: systemCurveDb(sets[c.eq], bands, c.fs, FREQS, c.eqOn) };
});

const out = { _comment: 'Written by tool/eq_cases.mjs from the firmware\'s eqband.js and syscurve.js - do not edit by hand.', freqs: FREQS, sets, free, clamp, retype, pass_q: passQ, stages };
const path = resolve(root, 'protocol', 'eq_cases.json');
const text = JSON.stringify(out, null, 1) + '\n';
if (process.argv.includes('--check')) {
  let current = '';
  try { current = readFileSync(path, 'utf8'); } catch { /* none yet */ }
  if (current !== text) {
    console.log('protocol/eq_cases.json differs from eqband.js and syscurve.js: run node tool/eq_cases.mjs');
    process.exit(1);
  }
} else {
  writeFileSync(path, text);
  console.log(`wrote protocol/eq_cases.json (${free.length} sets, ${stages.length} systems)`);
}
