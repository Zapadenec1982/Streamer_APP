// Module hooks for tool/now_faces.mjs: the firmware's webui/src/stores/now.js imports the web's
// i18n and WebSocket stores, which need a browser. For now.js alone those two are swapped for the
// stubs beside this file; `svelte/store` resolves from the firmware's own webui/node_modules.
let webui;

export async function initialize(data) {
  webui = data.webui;
}

export async function resolve(specifier, context, next) {
  const parent = context.parentURL || '';
  if (parent.endsWith('/stores/now.js') && (specifier === './i18n.js' || specifier === './state.js')) {
    return { url: new URL(specifier.replace('.js', '.mjs'), import.meta.url).href, shortCircuit: true };
  }
  if (specifier === 'svelte/store') {
    return next(specifier, { ...context, parentURL: new URL('package.json', webui).href });
  }
  return next(specifier, context);
}
