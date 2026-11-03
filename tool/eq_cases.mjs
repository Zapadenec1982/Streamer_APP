// eq_cases.mjs — the EQ edits, the whole system's curve and filters as text, from the firmware's
// own webui/src/lib/eqband.js, syscurve.js and eqfile.js, for protocol/eq_cases.json: the cases the app's Dart
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
const { parseFilters, formatFilters, bwToQ, slopeToQ } = await lib('eqfile.js');

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

// filters as text: what the web reads of REW, Equalizer APO and AutoEQ lines, and what it writes
const TEXTS = {
  rew: 'Filter Settings file\n\nPreamp: -6.4 dB\nFilter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.71\nFilter  2: ON  PK       Fc   47.0 Hz  Gain  -0.7 dB  Q  0.39\nFilter 3: OFF None\nFilter 4: ON None\nFilter: ON PEQ Fc 100 Hz Gain 1.0 dB BW Oct 0.167\n',
  kinds: 'Filter 1: ON LS 6dB Fc 100 Hz Gain 3 dB\nFilter 2: ON HSC 10.8 dB Fc 8 kHz Gain -4 dB\nFilter 3: ON LP Fc 18000 Hz\nFilter 4: ON HPQ Fc 30 Hz Q 0,5\nFilter 5: ON NO Fc 60 Hz Q 30\nFilter 6: ON BP Fc 1000 Hz Q 2\nFilter 7: ON Modal Fc 45 Hz Gain -8 dB Q 4\nFilter 8: ON LSC Fc 40 Hz Gain 9 dB\n',
  broken: 'Filter 1: ON PK Gain 3 dB Q 1\nFilter 2: ON PK Fc 1000 Hz Q 1\nFilter 3: ON PK Fc 1000 Hz Gain 3 dB\nFilter 4: ON\nFilter 5: ON PK Fc 5 Hz Gain 30 dB Q 20\nFilter 6: ON LSC 40 dB Fc 100 Hz Gain 6 dB\n',
  many: Array.from({ length: 13 }, (_, i) => `Filter ${i + 1}: ON PK Fc ${100 * (i + 1)} Hz Gain ${i % 5 - 2} dB Q 1.41`).join('\r\n'),
  empty: '# nothing here\n',
};
const parsed = Object.entries(TEXTS).map(([name, text]) => ({ name, text, ...parseFilters(text) }));
const written = Object.entries(sets).map(([name, bands]) => ({ name, text: formatFilters(bands, `P4 Player - ${name}`) }));
const widths = [0.167, 0.5, 1, 2].map((n) => ({ octaves: n, q: bwToQ(n) }));
const slopes = [[12, 6], [10.8, -4], [6, 3], [40, 6]].map(([s, g]) => ({ slope: s, gain: g, q: slopeToQ(s, g) }));

const out = { _comment: 'Written by tool/eq_cases.mjs from the firmware\'s eqband.js, syscurve.js and eqfile.js - do not edit by hand.', freqs: FREQS, sets, free, clamp, retype, pass_q: passQ, stages, files: { parsed, written, widths, slopes } };
const path = resolve(root, 'protocol', 'eq_cases.json');
const text = JSON.stringify(out, null, 1) + '\n';
if (process.argv.includes('--check')) {
  let current = '';
  try { current = readFileSync(path, 'utf8'); } catch { /* none yet */ }
  if (current !== text) {
    console.log('protocol/eq_cases.json differs from eqband.js, syscurve.js and eqfile.js: run node tool/eq_cases.mjs');
    process.exit(1);
  }
} else {
  writeFileSync(path, text);
  console.log(`wrote protocol/eq_cases.json (${free.length} sets, ${stages.length} systems)`);
}
