#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Find skin-tone variants where something that ISN'T skin changed value.

`build_tone_review.py` answers "is this still the same person, drawn the same
way" — a whole-set eyeball, one row per word. This answers a narrower question
that an eyeball is bad at across 556 words: **did the transform flip black and
white anywhere?**

Found on `paperboy` (2026-09-15), stepping Classic — Light to Dark: a black
t-shirt came back white, and a newspaper inverted from white-paper-with-black-
print to black-paper-with-white-print. Both changed elements sat directly
against skin, which is the tell — the model appears to read the prompt's
hairline "keep strong value contrast against the skin" line as a general licence
to preserve contrast, and flips whatever is adjacent to it.

## Why this is detectable without the model

A skin-tone step moves **mid-tones**: #F0B482 to #8D5524 is a walk through the
middle of the range. It has no business turning a near-white pixel near-black or
the reverse, anywhere in the picture — so those pixels are, by construction,
not-skin damage.

The detector is blunt on purpose: count pixels that are near-white in one image
and near-black in the other, both directions. No skin model, no segmentation,
nothing to tune per word. It cannot catch a subtler error — a navy shirt going
maroon — and is not meant to. It catches the one failure that is both severe and
invisible in a 556-row contact sheet.

## What it reads

The **shipped** art, `claudeBlast/TileImageSets/{cls,clsm,clsmd}_<key>.heic`,
not `tools/tile_sets/classic_chain_*` — those hold three sample tiles each, so
pointing at them silently audits almost nothing. HEIC is decoded with `sips`,
which ships with macOS, rather than adding a pillow-heif dependency to a repo
tool.

Usage:
    python3 tools/audit_tone_inversions.py                # both tones, open the page
    python3 tools/audit_tone_inversions.py --tone clsmd   # Dark only
    python3 tools/audit_tone_inversions.py --limit 60
    python3 tools/audit_tone_inversions.py --no-open
"""

import argparse
import base64
import io
import shutil
import subprocess
import tempfile
import webbrowser
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

SETS = Path("claudeBlast/TileImageSets")
OUT = Path("tools/tile_sets/tone_inversions")

BASE_PREFIX = "cls"
TONES = [
    ("clsm", "Medium", "🏽"),
    ("clsmd", "Dark", "🏿"),
]

# A pixel counts as flipped only when it crosses the whole range. Deliberately
# far apart: anything in between is the tone step doing its job, or antialiasing.
WHITE = 235
BLACK = 60
# Max chroma (max channel − min channel) for a pixel to count as neutral.
#
# This is the second thing that makes the audit usable, and `mouth` is why. Its
# Light tile is lips on a WHITE ground; the darker tones put the surrounding
# face behind them, so the background legitimately goes white → dark brown and a
# luminance-only test scored it 68% — the worst in the set, and perfectly
# correct art. Dark skin is warm brown with a wide channel spread; an inverted
# shirt or sheet of newsprint is neutral. Keeping the colour instead of
# flattening to luminance is what separates "skin arrived here" from "this got
# inverted", and it drops `mouth` from 68% to 3%.
NEUTRAL = 30
# Analysis size. The defect is large blocks — a shirt, a sheet of paper — so
# downscaling costs nothing and keeps 1,100 comparisons quick.
SIZE = 256
# Erosion kernel, in pixels at SIZE. This is what makes the audit usable.
#
# Counting flipped pixels raw flags half the set, because a tone step *redraws*
# the figure and it lands a pixel or two off register — so black line work falls
# where white was and the reverse, in roughly equal measure. That is drift, not
# damage, and it is thin. A real inversion is a solid region: a shirt, a sheet of
# paper. Eroding the mask deletes anything narrower than the kernel, which drops
# the noise by an order of magnitude (raw 9% → 1.5% on the worst person tiles)
# and leaves the blobs standing.
ERODE = 7
# Below this share of eroded mask, there is no region left worth looking at.
FLOOR = 0.001


def decode(paths: list[Path], into: Path) -> dict[Path, Path]:
    """HEIC → PNG via `sips`, in batches. Returns source → decoded."""
    into.mkdir(parents=True, exist_ok=True)
    out: dict[Path, Path] = {}
    batch = 200
    for i in range(0, len(paths), batch):
        chunk = paths[i : i + batch]
        subprocess.run(
            ["sips", "-s", "format", "png", "--out", str(into), *map(str, chunk)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        for p in chunk:
            # sips rewrites the extension for us.
            decoded = into / (p.stem + ".png")
            if decoded.is_file():
                out[p] = decoded
    return out


def load(path: Path) -> np.ndarray | None:
    """RGB at SIZE×SIZE, composited on white — the tiles' own ground.

    Colour is kept, not flattened to luminance: see `NEUTRAL`.
    """
    try:
        img = Image.open(path).convert("RGBA")
    except Exception:
        return None
    ground = Image.new("RGBA", img.size, (255, 255, 255, 255))
    flat = Image.alpha_composite(ground, img).convert("RGB")
    return np.asarray(flat.resize((SIZE, SIZE), Image.Resampling.BILINEAR), dtype=np.int32)


def luminance(rgb: np.ndarray) -> np.ndarray:
    """Rec. 601 luma. int32 throughout — 255 × 299 overflows an int16 array,
    which silently produced an all-zero mask and a clean bill of health."""
    return (rgb[..., 0] * 299 + rgb[..., 1] * 587 + rgb[..., 2] * 114) // 1000


def chroma(rgb: np.ndarray) -> np.ndarray:
    """Channel spread — near zero for black, white and grey; wide for skin."""
    return rgb.max(axis=-1) - rgb.min(axis=-1)


def erode(mask: np.ndarray, size: int) -> np.ndarray:
    """Drop structures thinner than `size`; a solid region survives."""
    im = Image.fromarray((mask * 255).astype(np.uint8), mode="L")
    return np.asarray(im.filter(ImageFilter.MinFilter(size))) > 127


def inversion(before: np.ndarray, after: np.ndarray) -> tuple[float, float, np.ndarray]:
    """Eroded share (the score), raw share, and the raw mask for display.

    Ranked on the eroded share so the list is regions rather than edges; the raw
    mask is what gets tinted, so a reviewer still sees the whole extent of what
    moved.
    """
    lb, la = luminance(before), luminance(after)
    # White → dark only counts where what it BECAME is neutral. Skin arriving in
    # a white area is the `mouth` case and is correct.
    to_dark = (lb >= WHITE) & (la <= BLACK) & (chroma(after) < NEUTRAL)
    # Dark → white only where what it WAS is neutral, so a saturated red going
    # pale is somebody else's bug, not this one. Skin never becomes white.
    to_light = (lb <= BLACK) & (la >= WHITE) & (chroma(before) < NEUTRAL)
    mask = to_dark | to_light
    return float(erode(mask, ERODE).mean()), float(mask.mean()), mask


def thumb(path: Path, mask: np.ndarray | None = None, px: int = 150) -> str:
    """Data URI for the review page, with flipped pixels tinted."""
    img = Image.open(path).convert("RGBA")
    ground = Image.new("RGBA", img.size, (255, 255, 255, 255))
    flat = Image.alpha_composite(ground, img).convert("RGB")
    if mask is not None and mask.any():
        # Tint what flipped, so the eye goes straight to it instead of hunting.
        overlay = Image.fromarray((mask * 255).astype(np.uint8), mode="L")
        overlay = overlay.resize(flat.size, Image.Resampling.NEAREST)
        flat = Image.composite(Image.new("RGB", flat.size, (255, 0, 190)), flat, overlay)
    flat.thumbnail((px, px))
    buf = io.BytesIO()
    flat.save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><title>Tone transform — value inversions</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font: 14px -apple-system, system-ui, sans-serif; margin: 24px;
         background: Canvas; color: CanvasText; }}
  h1 {{ font-size: 20px; margin: 0 0 4px; }}
  p.lede {{ color: GrayText; max-width: 62em; margin: 0 0 16px; }}
  table {{ border-collapse: collapse; }}
  td, th {{ padding: 6px 12px; text-align: left; vertical-align: middle; }}
  th {{ font-size: 12px; text-transform: uppercase; letter-spacing: .04em;
        color: GrayText; }}
  tr + tr {{ border-top: 1px solid color-mix(in srgb, CanvasText 12%, transparent); }}
  img {{ display: block; border-radius: 8px; background: #fff; }}
  .key {{ font-family: ui-monospace, Menlo, monospace; font-size: 13px; }}
  .score {{ font-variant-numeric: tabular-nums; font-weight: 600; }}
  .bad {{ color: #c62828; }}
  .meh {{ color: #a65c00; }}
  .cap {{ font-size: 11px; color: GrayText; }}
</style></head>
<body>
<h1>Tone transform — value inversions</h1>
<p class="lede">Neutral pixels that crossed the whole range — near-white to
near-black or back — between <strong>Classic&nbsp;—&nbsp;Light</strong> and a
darker tone. A skin-tone step moves mid-tones, so a full crossing into a
<em>neutral</em> value is never the skin: it is a shirt, a sheet of paper, or a
block of print that the transform flipped. Warm-brown arrivals are excluded,
because on a tile like <code>mouth</code> the darker tones legitimately put a
face where the Light tile had white.
<strong>Flipped pixels are tinted magenta</strong> in the variant — scan the
right-hand column and look at where the magenta is.</p>
<p class="lede">Ranked by <em>solid</em> flipped area, not raw pixel count. A
tone step redraws the figure and it lands a pixel or two off register, so black
line work falls where white was and back again — that is drift, it is thin, and
counting it raw flags half the set. The score is the share left after eroding
anything narrower than {erode}px, which is what a flipped shirt or sheet of
paper survives and a shifted outline does not. Magenta still shows the full
extent, so a row whose score is low and whose tint traces outlines is drift, and
a row with a magenta <em>blob</em> is the real thing.</p>
<p class="lede">{summary}</p>
<table>
<tr><th>Word</th><th>Tone</th><th>Flipped</th><th>Light</th><th>Variant</th></tr>
{rows}
</table>
</body></html>
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tone", choices=[t[0] for t in TONES], help="only this tone")
    ap.add_argument("--limit", type=int, default=80, help="rows to show (default 80)")
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()

    if not SETS.is_dir():
        raise SystemExit(f"No shipped art at {SETS}")
    if not shutil.which("sips"):
        raise SystemExit("`sips` not found — this tool needs macOS to decode HEIC")

    tones = [t for t in TONES if not args.tone or t[0] == args.tone]

    bases = sorted(SETS.glob(f"{BASE_PREFIX}_*.heic"))
    keys = [p.name[len(BASE_PREFIX) + 1 : -len(".heic")] for p in bases]

    wanted: list[Path] = list(bases)
    for prefix, _, _ in tones:
        wanted += [SETS / f"{prefix}_{k}.heic" for k in keys]
    wanted = [p for p in wanted if p.is_file()]

    print(f"Decoding {len(wanted)} images…")
    with tempfile.TemporaryDirectory() as tmp:
        decoded = decode(wanted, Path(tmp))

        cache: dict[Path, np.ndarray | None] = {}

        def lum(p: Path) -> np.ndarray | None:
            if p not in cache:
                d = decoded.get(p)
                cache[p] = load(d) if d else None
            return cache[p]

        findings = []
        scanned = 0
        for key in keys:
            before = lum(SETS / f"{BASE_PREFIX}_{key}.heic")
            if before is None:
                continue
            for prefix, label, emoji in tones:
                src = SETS / f"{prefix}_{key}.heic"
                after = lum(src)
                if after is None:
                    continue
                scanned += 1
                score, raw, mask = inversion(before, after)
                if score >= FLOOR:
                    findings.append((score, raw, key, prefix, label, emoji, mask))

        findings.sort(key=lambda f: -f[0])
        shown = findings[: args.limit]

        rows = []
        for score, raw, key, prefix, label, emoji, mask in shown:
            css = "bad" if score >= 0.01 else "meh"
            light = decoded[SETS / f"{BASE_PREFIX}_{key}.heic"]
            variant = decoded[SETS / f"{prefix}_{key}.heic"]
            rows.append(
                f'<tr><td class="key">{key}</td>'
                f"<td>{emoji} {label}</td>"
                f'<td class="score {css}">{score:.2%}'
                f'<span class="cap"> of {raw:.1%} raw</span></td>'
                f'<td><img src="{thumb(light)}"><span class="cap">Light</span></td>'
                f'<td><img src="{thumb(variant, mask)}">'
                f'<span class="cap">{label}</span></td></tr>'
            )

    summary = (
        f"{scanned} comparisons · {len(findings)} above the noise floor · "
        f"showing {len(shown)}."
    )
    if not findings:
        summary = f"{scanned} comparisons · nothing above the noise floor."

    OUT.mkdir(parents=True, exist_ok=True)
    page = OUT / "index.html"
    page.write_text(PAGE.format(rows="\n".join(rows), summary=summary, erode=ERODE))
    print(summary)
    print(f"→ {page}")
    if not args.no_open:
        webbrowser.open(page.resolve().as_uri())


if __name__ == "__main__":
    main()
