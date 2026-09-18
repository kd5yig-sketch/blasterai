#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Build the app icon from a shipped tile, framed in its Fitzgerald colour.

    Usage:
        python3 tools/make_app_icon.py --word speak
        python3 tools/make_app_icon.py --word speak --install
        python3 tools/make_app_icon.py --candidates speak say call talk --out /tmp/icons

The icon is the product's own vocabulary, drawn the way the product draws it: a
word's card, in the colour that word's part of speech carries on every board.
Nothing is invented for the icon, so it cannot drift from what the app looks
like — regenerate it and it follows.

COLOUR COMES FROM THE CODE, NOT FROM TASTE
------------------------------------------
`TileColorResolver.fitzgerald` in claudeBlast/Services/VocabularyClasses.swift is
the source of truth, and this script parses it rather than restating it. Colour
in this app means something clinical: a therapist teaches the Fitzgerald key, and
a verb is green on a published board the way it is green here. An icon that
picked a nicer green would be teaching a different key.

Note this is the *part of speech* axis, not the `wordClass` one. `speak` is
wordClass `actions`, which the old palette drew orange; since the Fitzgerald move
it is a verb, and verbs are green. Nouns are the orange ones.

DEBUG VS RETAIL
---------------
This builds the **retail** icon. The Debug icon is a separate asset
(`AppIcon`) and stays whatever it is, which is how a glance at the home screen
tells the two builds apart. That separation is load-bearing rather than
decorative: the Debug icon is third-party character art and must never reach a
shipped binary. `preflight_release.py` checks that the Release configuration does
not point at it.
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("pip install pillow")

RESOLVER = Path("claudeBlast/Services/VocabularyClasses.swift")
VOCAB = Path("claudeBlast/Resources/vocabulary.json")
TILES = Path("claudeBlast/TileImageSets")
RETAIL_ICONSET = Path("claudeBlast/Assets.xcassets/AppIconRetail.appiconset")
DEBUG_ICONSET = Path("claudeBlast/Assets.xcassets/AppIcon.appiconset")

SIZE = 1024
# The frame is wide enough to read as a colour at home-screen size. iOS masks the
# corners itself, so the canvas is a full-bleed square and only the inner plate
# is rounded.
FRAME = 96
PLATE_RADIUS = 96
# Art inset inside the white plate, so the drawing is not flush to its edge.
ART_PAD = 28

# The debug frame, and deliberately NOT a Fitzgerald colour.
#
# Every colour in this app means something on a board — a therapist teaches the
# key, and green is verbs. Hot pink belongs to no part of speech, so a build
# wearing it cannot be mistaken for a word, only for what it is. It also sits far
# enough from green to be unmistakable at home-screen size with both installed.
DEBUG_FRAME = (255, 20, 147)
BADGE_R = 108


def fitzgerald_colors() -> dict[str, tuple[int, int, int]]:
    """Parse `TileColorResolver.fitzgerald` so the icon cannot drift from the app."""
    if not RESOLVER.exists():
        sys.exit(f"missing {RESOLVER} — run from the repo root")
    body = RESOLVER.read_text()
    block = re.search(r"static func fitzgerald\(.*?\n    \}", body, re.S)
    if not block:
        sys.exit("could not find TileColorResolver.fitzgerald")
    out = {}
    for pos, r, g, b in re.findall(
            r"case \.(\w+):\s*return Color\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\)",
            block.group(0)):
        out[pos] = (round(float(r) * 255), round(float(g) * 255), round(float(b) * 255))
    return out


def part_of_speech(word: str) -> str:
    """The word's part of speech, by the app's own derivation.

    Three layers exist at runtime — a caregiver override on the tile, a bundled
    per-word index, then the word's class default. A bundled word with no
    caregiver override lands on the third, which is what the icon wants and what
    this reproduces: vocabulary.json gives the `wordClass`, and
    `VocabularyClasses.all` gives that class its `defaultPartOfSpeech`.
    """
    vocab = json.loads(VOCAB.read_text())
    entry = next((w for w in vocab if w["key"] == word), None)
    if entry is None:
        sys.exit(f"'{word}' is not in {VOCAB}")
    word_class = entry["wordClass"]

    classes = Path("claudeBlast/Services/VocabularyClasses.swift").read_text()
    m = re.search(rf'VocabularyClass\(name: "{re.escape(word_class)}",\s*'
                  rf'defaultPartOfSpeech: \.(\w+)', classes)
    if not m:
        sys.exit(f"wordClass '{word_class}' has no defaultPartOfSpeech")
    return m.group(1)


def tile_png(word: str, image_set: str, workdir: Path) -> Path:
    """Decode a shipped HEIC tile. `sips` rather than a Pillow HEIC plugin,
    because it is on every Mac and this must not need a pip install to run."""
    heic = TILES / f"{image_set}_{word}.heic"
    if not heic.exists():
        sys.exit(f"no art: {heic}")
    png = workdir / f"{word}.png"
    subprocess.run(["sips", "-s", "format", "png", str(heic), "--out", str(png)],
                   capture_output=True, check=True)
    return png


def badge(icon: Image.Image) -> None:
    """A white disc in the corner, so the debug build is marked as well as
    coloured — colour alone is a convention someone has to have been told."""
    d = ImageDraw.Draw(icon)
    # Inset well clear of the corner: iOS masks the icon to a rounded square
    # with a large radius, so anything sitting in the literal corner is cut.
    cx = cy = SIZE - BADGE_R - FRAME
    d.ellipse([cx - BADGE_R, cy - BADGE_R, cx + BADGE_R, cy + BADGE_R],
              fill=(255, 255, 255), outline=DEBUG_FRAME, width=14)
    for path in ["/System/Library/Fonts/SFNSRounded.ttf",
                 "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                 "/Library/Fonts/Arial Bold.ttf"]:
        if Path(path).exists():
            font = ImageFont.truetype(path, 92)
            d.text((cx, cy), "DEV", font=font, fill=DEBUG_FRAME, anchor="mm")
            return
    # No usable font: the disc alone still marks it.


def compose(word: str, image_set: str, color: tuple[int, int, int],
            workdir: Path, variant: str = "retail") -> Image.Image:
    icon = Image.new("RGB", (SIZE, SIZE), color)

    plate = Image.new("L", (SIZE - 2 * FRAME, SIZE - 2 * FRAME), 0)
    ImageDraw.Draw(plate).rounded_rectangle(
        [0, 0, plate.size[0] - 1, plate.size[1] - 1], radius=PLATE_RADIUS, fill=255)

    art = Image.open(tile_png(word, image_set, workdir)).convert("RGB")
    inner = plate.size[0] - 2 * ART_PAD
    art = art.resize((inner, inner), Image.LANCZOS)

    white = Image.new("RGB", plate.size, (255, 255, 255))
    white.paste(art, (ART_PAD, ART_PAD))
    icon.paste(white, (FRAME, FRAME), plate)
    if variant == "debug":
        badge(icon)
    return icon


def build(word: str, image_set: str, out_dir: Path,
          variant: str = "retail") -> Path:
    pos = part_of_speech(word)
    colors = fitzgerald_colors()
    if pos not in colors:
        sys.exit(f"'{word}' is a {pos}, which fitzgerald() does not colour")
    frame = DEBUG_FRAME if variant == "debug" else colors[pos]
    with tempfile.TemporaryDirectory() as tmp:
        icon = compose(word, image_set, frame, Path(tmp), variant)
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"AppIcon-{word}-{variant}.png"
    icon.save(path)
    print(f"  {word:<8} {pos:<10} {variant:<7} rgb{frame}  →  {path}")
    return path


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Build the retail app icon from a shipped tile.")
    ap.add_argument("--word", help="the tile to use, e.g. speak")
    ap.add_argument("--candidates", nargs="+",
                    help="build several for comparison instead of one")
    ap.add_argument("--set", dest="image_set", default="cls",
                    help="image set prefix (default cls, Classic Light)")
    ap.add_argument("--out", type=Path, default=Path("build/icons"),
                    help="where to write (default build/icons)")
    ap.add_argument("--variant", choices=["retail", "debug"], default="retail",
                    help="retail = Fitzgerald frame; debug = hot pink + DEV badge")
    ap.add_argument("--install", action="store_true",
                    help=f"also write {RETAIL_ICONSET}/AppIcon.png")
    args = ap.parse_args()

    if not args.word and not args.candidates:
        ap.error("pass --word or --candidates")

    for word in (args.candidates or [args.word]):
        path = build(word, args.image_set, args.out, args.variant)

    if args.install:
        if args.candidates:
            sys.exit("--install needs a single --word, not --candidates")
        target = (DEBUG_ICONSET if args.variant == "debug" else RETAIL_ICONSET)
        target.mkdir(parents=True, exist_ok=True)
        Image.open(path).save(target / "AppIcon.png")
        print(f"installed → {target}/AppIcon.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
