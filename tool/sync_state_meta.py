#!/usr/bin/env python3
"""
sync_state_meta.py — the panel's state keys as the app knows them: protocol/state_meta.json.

The firmware builds state_meta (its data/ui.json, served as GET /api/ui) from the state sections of
the modules' manifests, in tools/generate_ui.py. data/ui.json is build output and not in git, so
this reads the manifests themselves (modules/<name>/manifest.json for the modules project.json
names) and makes the same projection: type, access, unit, and for a writable key its options or
min/max/step. test/keys_test.dart holds the app's key constants to the result. MODESP_PLAYER_ROOT
names the firmware checkout (default: ../modesp-player beside this repository).

    python3 tool/sync_state_meta.py           # rewrite protocol/state_meta.json
    python3 tool/sync_state_meta.py --check   # exit 1 if it is out of date
"""

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "protocol" / "state_meta.json"


def firmware_root():
    fw = Path(os.environ.get("MODESP_PLAYER_ROOT", ROOT.parent / "modesp-player")).resolve()
    if not (fw / "project.json").is_file():
        raise SystemExit(f"no firmware checkout at {fw}: set MODESP_PLAYER_ROOT")
    return fw


def project(info):
    """One key's entry, as generate_ui.py writes it into state_meta."""
    entry = {"type": info.get("type", "string"), "access": info.get("access", "read")}
    if info.get("unit"):
        entry["unit"] = info["unit"]
    if info.get("access") == "readwrite":
        if "options" in info:
            entry["options"] = info["options"]
        else:
            for prop in ("min", "max", "step"):
                if prop in info:
                    entry[prop] = info[prop]
    return entry


def render():
    fw = firmware_root()
    modules = json.loads((fw / "project.json").read_text(encoding="utf-8")).get("modules", [])
    meta = {}
    for name in modules:
        manifest = json.loads((fw / "modules" / name / "manifest.json").read_text(encoding="utf-8"))
        for key, info in manifest.get("state", {}).items():
            meta[key] = project(info)
    return json.dumps(dict(sorted(meta.items())), ensure_ascii=False, indent=2) + "\n"


def main(argv):
    text = render()
    if "--check" in argv:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != text:
            print(f"{OUT.relative_to(ROOT)} is out of date: run python3 tool/sync_state_meta.py")
            return 1
        return 0
    OUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
