#!/usr/bin/env python3
"""
sync_eq_vectors.py — the EQ curve as the firmware designs it: protocol/eq_curve_vectors.json.

The firmware's host test writes the vectors from the audio core's own design
(tests/host/test_eq_curve_vectors.cpp → tests/host/fixtures/eq_curve/vectors.json): bands, each
band's response matched and bilinear, and the summed curve the glass draws. The web's eqmath.js is
held to them, and so is the app's port (lib/device/eq_math.dart, test/eq_math_test.dart). This
keeps the app's copy the same file. MODESP_PLAYER_ROOT names the firmware checkout (default:
../modesp-player beside this repository).

    python3 tool/sync_eq_vectors.py           # copy the vectors
    python3 tool/sync_eq_vectors.py --check   # exit 1 if the copy differs
"""

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "protocol" / "eq_curve_vectors.json"
SOURCE = Path("tests") / "host" / "fixtures" / "eq_curve" / "vectors.json"


def source():
    fw = Path(os.environ.get("MODESP_PLAYER_ROOT", ROOT.parent / "modesp-player")).resolve()
    path = fw / SOURCE
    if not path.is_file():
        raise SystemExit(f"no {SOURCE} in {fw}: set MODESP_PLAYER_ROOT")
    return path.read_bytes()


def main(argv):
    data = source()
    if "--check" in argv:
        current = OUT.read_bytes() if OUT.exists() else b""
        if current != data:
            print(f"{OUT.relative_to(ROOT)} is out of date: run python3 tool/sync_eq_vectors.py")
            return 1
        return 0
    OUT.write_bytes(data)
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
