#!/usr/bin/env python3
"""
gen_l10n.py — the app's strings in four languages as ARB files: lib/l10n/app_<lang>.arb.

What the web already says is not written again. l10n/shared.txt lists the web catalog keys the app
uses; their texts come from the firmware's webui/src/i18n/<lang>.json. Strings only the app has
are in l10n/app_<lang>.json, in the web's own format: flat dotted keys, {placeholders}, a plural
as KEY.one/.few/.many/.other. Both become ARB under camelCase names (nav.player → navPlayer), a
plural one ICU message over {n}. MODESP_PLAYER_ROOT names the firmware checkout (default:
../modesp-player beside this repository). flutter gen-l10n then reads the ARB files (l10n.yaml).

    python3 tool/gen_l10n.py           # rewrite lib/l10n/*.arb
    python3 tool/gen_l10n.py --check   # exit 1 if they are out of date
"""

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGS = ["uk", "en", "de", "pl"]          # the web's four; en is the ARB template
TEMPLATE = "en"
PLURAL = ["zero", "one", "two", "few", "many", "other"]
OUT_DIR = ROOT / "lib" / "l10n"
PLACEHOLDER = re.compile(r"\{(\w+)\}")


def firmware_root():
    fw = Path(os.environ.get("MODESP_PLAYER_ROOT", ROOT.parent / "modesp-player")).resolve()
    if not (fw / "webui" / "src" / "i18n" / "en.json").is_file():
        raise SystemExit(f"no firmware checkout at {fw}: set MODESP_PLAYER_ROOT")
    return fw


def camel(key):
    parts = re.split(r"[._]", key)
    name = parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])
    if not re.fullmatch(r"[a-z][A-Za-z0-9]*", name):
        raise SystemExit(f"{key!r} does not make a Dart name ({name!r})")
    return name


def check_braces(key, text):
    if PLACEHOLDER.sub("", text).count("{") or PLACEHOLDER.sub("", text).count("}"):
        raise SystemExit(f"{key!r}: braces other than {{placeholders}} in {text!r}")


def message(catalog, key, where):
    """(ARB text, {placeholder: type}) for one key — a plural when KEY.one … are there."""
    if key in catalog:
        check_braces(key, catalog[key])
        return catalog[key], {p: "String" for p in PLACEHOLDER.findall(catalog[key])}
    forms = [(f, catalog[f"{key}.{f}"]) for f in PLURAL if f"{key}.{f}" in catalog]
    if not forms or forms[-1][0] != "other":
        raise SystemExit(f"{key!r} is missing from {where}")
    for f, text in forms:
        check_braces(f"{key}.{f}", text)
    cases = " ".join(f"{f}{{{text}}}" for f, text in forms)
    return f"{{n, plural, {cases}}}", {"n": "int"}


def keys_of(path):
    lines = path.read_text(encoding="utf-8").splitlines()
    return [ln.strip() for ln in lines if ln.strip() and not ln.lstrip().startswith("#")]


def render():
    fw = firmware_root()
    shared = keys_of(ROOT / "l10n" / "shared.txt")
    out = {}
    names = {}
    for lang in LANGS:
        web = json.loads((fw / "webui" / "src" / "i18n" / f"{lang}.json").read_text(encoding="utf-8"))
        own = json.loads((ROOT / "l10n" / f"app_{lang}.json").read_text(encoding="utf-8"))
        own_keys = sorted({re.sub(r"\.(%s)$" % "|".join(PLURAL), "", k) for k in own})
        clash = set(own_keys) & set(shared)
        if clash:
            raise SystemExit(f"app_{lang}.json repeats web keys: {sorted(clash)}")
        arb = {"@@locale": lang}
        for key, catalog, where in [(k, web, f"webui/src/i18n/{lang}.json") for k in shared] + \
                                   [(k, own, f"l10n/app_{lang}.json") for k in own_keys]:
            name = camel(key)
            if names.setdefault(name, key) != key:
                raise SystemExit(f"{key!r} and {names[name]!r} both become {name!r}")
            text, params = message(catalog, key, where)
            arb[name] = text
            if lang == TEMPLATE:
                meta = {"description": key}
                if params:
                    meta["placeholders"] = {p: {"type": t} for p, t in params.items()}
                arb["@" + name] = meta
        out[lang] = arb
    template_keys = [k for k in out[TEMPLATE] if not k.startswith("@")]
    for lang in LANGS:
        keys = [k for k in out[lang] if not k.startswith("@")]
        if keys != template_keys:
            raise SystemExit(f"{lang}: keys differ from {TEMPLATE}: {sorted(set(keys) ^ set(template_keys))}")
    return {lang: json.dumps(arb, ensure_ascii=False, indent=2) + "\n" for lang, arb in out.items()}


def main(argv):
    files = render()
    stale = []
    for lang, text in files.items():
        path = OUT_DIR / f"app_{lang}.arb"
        current = path.read_text(encoding="utf-8") if path.exists() else ""
        if current != text:
            stale.append(path)
            if "--check" not in argv:
                path.write_text(text, encoding="utf-8")
                print(f"wrote {path.relative_to(ROOT)}")
    if "--check" in argv and stale:
        print("out of date: " + ", ".join(str(p.relative_to(ROOT)) for p in stale)
              + " — run python3 tool/gen_l10n.py")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
