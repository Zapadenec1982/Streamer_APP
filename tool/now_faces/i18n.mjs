// Stub of the web's stores/i18n.js for now.js: a catalog key is the key itself.
export const K = (key) => key;
export const fmt = (s, params = {}) => String(s ?? '').replace(/\{(\w+)\}/g, (m, k) => (k in params ? params[k] : m));
