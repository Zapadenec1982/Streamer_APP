// now_faces.mjs — what the web shows for a panel state, from the firmware's own now.js, for
// protocol/now_faces.json: the fixtures the app's Dart port of the same face is tested on.
//
// The cases (name and state) are written by hand; the face of each is computed here by running
// the firmware's webui/src/stores/now.js under Node, so the fixtures say what the web says.
// Transport is left out: every source's buttons are audio.transport now, and which ones a source
// takes is the panel's audio.transport_caps. MODESP_PLAYER_ROOT names the firmware checkout
// (default ../modesp-player); its webui/node_modules must be installed.
//
//   node tool/now_faces.mjs           # rewrite the faces in protocol/now_faces.json
//   node tool/now_faces.mjs --check   # exit 1 if they differ from what now.js says
import { register } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fw = resolve(process.env.MODESP_PLAYER_ROOT || resolve(root, '..', 'modesp-player'));
const webui = pathToFileURL(resolve(fw, 'webui') + '/').href;
register('./now_faces/hooks.mjs', import.meta.url, { data: { webui } });

// svelte's get(): a subscription read once and dropped
const get = (store) => {
  let value;
  store.subscribe((v) => (value = v))();
  return value;
};
const { state } = await import(new URL('./now_faces/state.mjs', import.meta.url).href);
const { now } = await import(new URL('src/stores/now.js', webui).href);

const FIELDS = ['kind', 'source', 'icon', 'nameKey', 'fromKey', 'device', 'title', 'titleKey', 'subtitle',
  'subtitleKey', 'subtitleArgs', 'format', 'playing', 'live', 'progress', 'pos', 'dur', 'seekKey', 'repeat', 'shuffle'];

const path = resolve(root, 'protocol', 'now_faces.json');
const cases = JSON.parse(readFileSync(path, 'utf8'));
for (const c of cases) {
  state.set(c.state);
  const face = get(now);
  c.face = Object.fromEntries(FIELDS.map((f) => [f, face[f] === undefined ? null : face[f]]));
}
const text = JSON.stringify(cases, null, 2) + '\n';
if (process.argv.includes('--check')) {
  if (readFileSync(path, 'utf8') !== text) {
    console.log('protocol/now_faces.json differs from now.js: run node tool/now_faces.mjs');
    process.exit(1);
  }
} else {
  writeFileSync(path, text);
  console.log(`wrote protocol/now_faces.json (${cases.length} cases)`);
}
