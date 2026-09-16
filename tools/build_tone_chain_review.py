#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Is the Classic tone ladder actually stepping, and by how much?

`build_tone_review.py` answers "is this still the same person, drawn the same
way" — a whole-set eyeball. This answers the other question: **does each rung
differ enough from the one above it to be worth being a separate set**, and
where does the ladder sit against the Apple emoji reference.

## The fourth folder

`classic_chain_dark` is not shipped and is not tracked in git. It exists because
a mis-issued `--build all --chain` generated it (2026-09-15: `--build all` means
all *tones*, and silently ignores `--tiles`), and it was kept deliberately:

    "they represent a nice limit reference that we want to always remain
     lighter than"  — Mark, 2026-09-15

So it is the floor. The three shipped tones should sit above it, and if a future
regeneration lands a shipped tone at or below that line, the ladder has run off
its own bottom end. Nothing else in the repo records where that bottom is.

It is untracked on purpose — 259 PNGs at ~1 MB would want Git LFS, and the LFS
boundary is deliberately narrow (see docs). A `git clean -x` will take it; that
is the accepted cost.

## Reading the output

Rows are sorted by how much the **Medium-Dark → Dark** step moved, worst first,
because a rung that barely moved is the interesting one. The number under each
key is luma lost on that step, measured on the same pixels in both images.

Usage:
    python3 tools/build_tone_chain_review.py
    python3 tools/build_tone_chain_review.py --no-open
    python3 tools/build_tone_chain_review.py --limit 40
"""

import argparse
import base64
import io
import json
import webbrowser
from pathlib import Path

import numpy as np
from PIL import Image

BASE = Path("tools/tile_sets")
OUT = BASE / "tone_chain_review"
SKIN_CACHE = BASE / "classic_skin_tiles.json"

# Apple Color Emoji swatch luma, for orientation. Our ladder deliberately does
# not match these — Classic's declared Light target is #F0B482 (luma ~192),
# darker than 🏻 — but the gaps between rungs are comparable.
EMOJI = {"Light": 224.1, "Medium": 150.4, "Medium-Dark": 108.9, "Dark": 72.4}

SETS = [
    ("classic", "Light", "cls — ships"),
    ("classic_chain_medium", "Medium", "clsm — ships"),
    ("classic_chain_medium_dark", "Medium-Dark", "clsmd — ships, labelled “Dark” in the app"),
    ("classic_chain_dark", "Dark", "not shipped — the limit we stay lighter than"),
]


def rgb(path: Path, size: int) -> np.ndarray:
    im = Image.open(path).convert("RGBA")
    ground = Image.new("RGBA", im.size, (255, 255, 255, 255))
    flat = Image.alpha_composite(ground, im).convert("RGB")
    return np.asarray(flat.resize((size, size), Image.BILINEAR), dtype=np.int32)


def luma(a: np.ndarray) -> np.ndarray:
    return (a[..., 0] * 299 + a[..., 1] * 587 + a[..., 2] * 114) // 1000


def skin_mask(light: np.ndarray) -> np.ndarray:
    """Skin in the LIGHT master: warm, red>green>blue, neither paper nor outline.

    Located once and reused for every rung, so the comparison is of tone and
    nothing else — a mask recomputed per variant would drift with the art.
    """
    r, g, b = light[..., 0], light[..., 1], light[..., 2]
    l = luma(light)
    return (r > g) & (g > b) & (r - b > 35) & (l > 120) & (l < 235)


def thumb(path: Path, px: int = 160) -> str:
    im = Image.open(path).convert("RGBA")
    ground = Image.new("RGBA", im.size, (255, 255, 255, 255))
    flat = Image.alpha_composite(ground, im).convert("RGB")
    flat.thumbnail((px, px))
    buf = io.BytesIO()
    flat.save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


PAGE = """<!doctype html><meta charset=utf-8><title>Classic tone ladder</title>
<style>
:root{{color-scheme:light dark}}
body{{font:14px -apple-system,system-ui,sans-serif;margin:24px;background:Canvas;color:CanvasText}}
h1{{font-size:20px;margin:0 0 4px}}
p{{color:GrayText;max-width:64em}}
table{{border-collapse:collapse}} td,th{{padding:6px 10px;vertical-align:top;text-align:left}}
th{{font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:GrayText}}
tr+tr{{border-top:1px solid color-mix(in srgb,CanvasText 12%,transparent)}}
img{{display:block;border-radius:8px;background:#fff}}
.k{{font:13px ui-monospace,Menlo,monospace}}
.d{{font-weight:600;font-variant-numeric:tabular-nums}}
.bad{{color:#c62828}} .meh{{color:#a65c00}} .ok{{color:#2e7d32}}
.c{{font-size:10px;color:GrayText;margin-top:2px}}
</style>
<h1>Classic tone ladder</h1>
<p>{summary}</p>
<p>Ranked by how far the <strong>Medium-Dark → Dark</strong> step moved, smallest
first: a rung that barely moves is the one worth looking at. The figure under
each key is luma lost on that step, measured on the same skin pixels in both.
<strong>Dark does not ship</strong> — it is kept as the floor the three shipped
tones should stay lighter than.</p>
<table><tr><th>Word</th>{headers}</tr>
{rows}
</table>
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=60)
    ap.add_argument("--no-open", action="store_true")
    ap.add_argument("--size", type=int, default=256, help="analysis resolution")
    args = ap.parse_args()

    missing = [f for f, _, _ in SETS if not (BASE / f).is_dir()]
    if missing:
        raise SystemExit(f"Missing set folders: {missing}")

    cache = json.loads(SKIN_CACHE.read_text()) if SKIN_CACHE.exists() else {}
    keys = [k for k, has_skin in cache.items() if has_skin
            and all((BASE / f / f"{k}.png").is_file() for f, _, _ in SETS)]
    if not keys:
        raise SystemExit("No tiles present in all four sets — is classic_chain_dark built?")

    # Ladder averages, for the summary line.
    means = {label: [] for _, label, _ in SETS}
    scored = []
    for k in keys:
        light = rgb(BASE / "classic" / f"{k}.png", args.size)
        mask = skin_mask(light)
        if mask.sum() < 200:
            continue
        per = {}
        for folder, label, _ in SETS:
            v = luma(rgb(BASE / folder / f"{k}.png", args.size))[mask].mean()
            per[label] = v
            means[label].append(v)
        scored.append((per["Medium-Dark"] - per["Dark"], k))

    scored.sort()
    shown = scored[: args.limit]

    ladder = " · ".join(
        f"{label} {np.mean(means[label]):.0f} (emoji {EMOJI[label]:.0f})"
        for _, label, _ in SETS)
    summary = (f"{len(scored)} tiles with skin, present in all four sets. "
               f"Mean skin luma — {ladder}.")

    headers = "".join(f"<th>{label}<div class=c>{note}</div></th>"
                      for _, label, note in SETS)
    rows = []
    for delta, k in shown:
        cls = "bad" if delta < 5 else ("meh" if delta < 15 else "ok")
        cells = "".join(f'<td><img src="{thumb(BASE / f / f"{k}.png")}"></td>'
                        for f, _, _ in SETS)
        rows.append(f'<tr><td class="k">{k}<div class="d {cls}">{delta:+.0f}</div></td>{cells}</tr>')

    OUT.mkdir(parents=True, exist_ok=True)
    page = OUT / "index.html"
    page.write_text(PAGE.format(summary=summary, headers=headers, rows="\n".join(rows)))
    print(summary)
    print(f"→ {page}")
    if not args.no_open:
        webbrowser.open(page.resolve().as_uri())


if __name__ == "__main__":
    main()
