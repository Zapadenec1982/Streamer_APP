#!/usr/bin/env python3
"""app_icon.py — the app's mark as pictures: the launcher PNGs for Android 7 (which has no
adaptive icons), the Google Play icon and the Play feature graphic.

The mark is android/app/src/main/res/drawable/ic_launcher_foreground.xml: a speaker's driver in
the panel's amber scheme, on a 108-unit canvas of which a launcher shows the middle 72. This draws
the same circles, four times over and scaled down, so the edges come out smooth. The feature
graphic sets the app's name in Roboto from the Flutter SDK (FLUTTER_ROOT, or the flutter on PATH).
Needs Pillow.
"""
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android" / "app" / "src" / "main" / "res"
STORE = ROOT / "store"

BACKGROUND = (0x23, 0x1F, 0x18)      # ic_launcher_background.xml
AMBER = (0xFF, 0xB9, 0x5F)           # primary
CONE = (0x65, 0x3E, 0x00)            # primaryContainer
TEXT = (0xEB, 0xE1, 0xD5)            # onSurface
RIDGE_ALPHA = 0x59
SUPER = 4

LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def mark(draw, cx, cy, unit):
    """The driver, centred on (cx, cy), one canvas unit = unit pixels."""
    def circle(r, **kw):
        draw.ellipse([cx - r * unit, cy - r * unit, cx + r * unit, cy + r * unit], **kw)

    circle(19, fill=CONE)
    circle(25 + 2.5, outline=AMBER, width=round(5 * unit))
    circle(14 + 0.75, outline=AMBER + (RIDGE_ALPHA,), width=max(1, round(1.5 * unit)))
    circle(8.5, fill=AMBER)


def square(size, shown=72):
    """The icon as a launcher shows it: the middle [shown] units of the canvas, [size] px wide."""
    big = size * SUPER
    img = Image.new("RGBA", (big, big), BACKGROUND + (255,))
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    mark(ImageDraw.Draw(layer), big / 2, big / 2, big / shown)
    img.alpha_composite(layer)
    return img


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, mask=mask)
    return out


def roboto(weight):
    flutter = os.environ.get("FLUTTER_ROOT") or str(Path(shutil.which("flutter")).resolve().parents[1])
    font = Path(flutter) / "bin" / "cache" / "artifacts" / "material_fonts" / f"Roboto-{weight}.ttf"
    if not font.is_file():
        raise SystemExit(f"no {font}: set FLUTTER_ROOT")
    return font


def feature_graphic():
    """1024×500: the mark and the name side by side, centred, on the icon's ground."""
    w, h = 1024 * SUPER, 500 * SUPER
    img = Image.new("RGBA", (w, h), BACKGROUND + (255,))
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    name = "ModESP Streamer"
    font = ImageFont.truetype(str(roboto("Medium")), 64 * SUPER)
    unit = 5 * SUPER
    radius = 27.5 * unit
    gap = 56 * SUPER
    left = (w - (2 * radius + gap + font.getlength(name))) / 2
    mark(draw, left + radius, h / 2, unit)
    draw.text((left + 2 * radius + gap, h / 2), name, font=font, fill=TEXT, anchor="lm")
    img.alpha_composite(layer)
    return img.resize((1024, 500), Image.LANCZOS).convert("RGB")


def main(argv):
    for density, px in LEGACY.items():
        icon = rounded(square(px), px * SUPER * 0.22).resize((px, px), Image.LANCZOS)
        icon.save(RES / f"mipmap-{density}" / "ic_launcher.png")
    # Google Play rounds the corners itself: a full square
    square(512).resize((512, 512), Image.LANCZOS).convert("RGB").save(STORE / "icon_512.png")
    feature_graphic().save(STORE / "feature_graphic.png")
    print("wrote the launcher PNGs, store/icon_512.png, store/feature_graphic.png")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
