#!/usr/bin/env python3
"""Render Data/splash.png (the loading window shown at launch) with the
game's name and version.

The name and version come from APP_DISPLAY_NAME / APP_DISPLAY_VERSION in the
top-level CMakeLists.txt, so after bumping the version there just run:

    python3 tools/splash/make_splash.py

and commit the new Data/splash.png. Needs Pillow.
"""
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
BASE = Path(__file__).with_name("splash-base.png")
FONT = ROOT / "Data" / "Roboto-Light.ttf"
OUT = ROOT / "Data" / "splash.png"


def cmake_var(name):
    text = (ROOT / "CMakeLists.txt").read_text()
    m = re.search(r'set\(\s*%s\s+"([^"]*)"\s*\)' % name, text)
    if not m:
        raise SystemExit(f"{name} not found in CMakeLists.txt")
    return m.group(1)


def main():
    name = cmake_var("APP_DISPLAY_NAME")
    version = cmake_var("APP_DISPLAY_VERSION")

    img = Image.open(BASE).convert("RGBA")

    # title: upper case, italic look (Roboto Light sheared), left at x=16
    title_font = ImageFont.truetype(str(FONT), 30)
    title = name.upper()
    l, t, r, b = title_font.getbbox(title)
    layer = Image.new("RGBA", (r + 40, b + 10), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((10, 0), title, font=title_font, fill=(255, 255, 255, 255))
    shear = 0.2
    layer = layer.transform(
        layer.size, Image.AFFINE, (1, shear, -shear * layer.size[1], 0, 1, 0),
        resample=Image.BICUBIC)
    img.alpha_composite(layer, (16 - 10, 18 - t))

    # version: right aligned under the title, as the original splash had it
    ver_font = ImageFont.truetype(str(FONT), 17)
    text = f"Version {version}"
    l, t, r, b = ver_font.getbbox(text)
    ImageDraw.Draw(img).text((284 - r, 47 - t), text, font=ver_font, fill=(240, 240, 240, 255))

    img.save(OUT)
    print(f"wrote {OUT.relative_to(ROOT)}: {title} / {text}")


if __name__ == "__main__":
    main()
