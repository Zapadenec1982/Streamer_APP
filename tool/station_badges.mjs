// station_badges.mjs — a station's stand-in disc, from the firmware's own
// webui/src/lib/stationbadge.js (the glass's station_badge.h copied for the web), for
// protocol/station_badges.json: the cases the app's Dart port (lib/ui/station_badge.dart) is
// tested on. The names are written by hand — the glass's pinned cases and a few more; the discs
// are what stationbadge.js says. MODESP_PLAYER_ROOT names the firmware checkout (default
// ../modesp-player).
//
//   node tool/station_badges.mjs           # rewrite the discs
//   node tool/station_badges.mjs --check   # exit 1 if they differ from stationbadge.js
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fw = resolve(process.env.MODESP_PLAYER_ROOT || resolve(root, '..', 'modesp-player'));
const { stationBadge } = await import(pathToFileURL(resolve(fw, 'webui/src/lib/stationbadge.js')).href);

const path = resolve(root, 'protocol', 'station_badges.json');
const cases = JSON.parse(readFileSync(path, 'utf8'));
for (const c of cases) c.badge = stationBadge(c.name);
const text = JSON.stringify(cases, null, 2) + '\n';
if (process.argv.includes('--check')) {
  if (readFileSync(path, 'utf8') !== text) {
    console.log('protocol/station_badges.json differs from stationbadge.js: run node tool/station_badges.mjs');
    process.exit(1);
  }
} else {
  writeFileSync(path, text);
  console.log(`wrote protocol/station_badges.json (${cases.length} names)`);
}
