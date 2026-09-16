#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Is `tools/tile_sets/` ahead of what the app actually ships?

Tile art has two homes. Masters live in `tools/tile_sets/{set}/{key}.png`, and
the app bundle carries `claudeBlast/TileImageSets/{prefix}_{key}.heic`, produced
by `optimize_tiles.py` then `sync_to_app.py`. **Nothing connected them.** Edit a
master, forget the two-step sync, and the repo looks clean while the app ships
the old picture.

That is not hypothetical. On 2026-09-16 this was found by accident: seven tone
masters had been regenerated two days earlier to fix blond hair on dark skin —
the failure `build_tone_variants` itself calls "the most common mistake made on
this task" — and the fix had never reached the bundle. The app shipped the blond
version for two days. It surfaced only because an unrelated word needed syncing
and the run happened to pick them up.

## Why git, not mtimes

A fresh clone gives every file the same checkout time, so mtimes would report the
entire set as drifted, and a check that cries wolf is a check nobody runs. The
commit that last touched each file is stable across clones and is what actually
answers "which of these two is newer".

Untracked masters are reported separately: they have no history to compare, and
a new master nobody has synced is exactly the case worth catching.

Usage:
    python3 tools/check_tileset_drift.py          # report; exit 1 on drift
    python3 tools/check_tileset_drift.py --quiet  # exit code only
"""

import argparse
import subprocess
import sys
from pathlib import Path

MASTERS = Path("tools/tile_sets")
BUNDLE = Path("claudeBlast/TileImageSets")

# Mirrors `sync_to_app.SET_PREFIX`. Duplicated rather than imported because that
# module runs argparse at import time; if the two drift, this check drifts with
# them, so keep them together.
SET_PREFIX = {
    "playful_3d": "p3d",
    "high_contrast_v2": "hc",
    "classic": "cls",
    "classic_chain_medium": "clsm",
    "classic_chain_medium_dark": "clsmd",
}


def commit_times() -> dict[str, int]:
    """Path → unix time of the newest commit touching it. One git call."""
    out = subprocess.run(
        ["git", "log", "--pretty=format:@%ct", "--name-only", "--",
         str(MASTERS), str(BUNDLE)],
        capture_output=True, text=True, check=True).stdout
    times: dict[str, int] = {}
    now = 0
    for line in out.splitlines():
        if line.startswith("@"):
            now = int(line[1:])
        elif line.strip():
            # First mention wins: git log is newest-first.
            times.setdefault(line.strip(), now)
    return times


def tracked() -> set[str]:
    out = subprocess.run(["git", "ls-files", str(MASTERS), str(BUNDLE)],
                         capture_output=True, text=True, check=True).stdout
    return set(out.split())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    times, known = commit_times(), tracked()
    stale: list[tuple[str, str]] = []     # master newer than what ships
    unsynced: list[str] = []              # master with no shipped counterpart
    untracked_masters: list[str] = []     # never committed, so never synced

    for folder, prefix in SET_PREFIX.items():
        src_dir = MASTERS / folder
        if not src_dir.is_dir():
            continue
        for src in sorted(src_dir.glob("*.png")):
            dst = BUNDLE / f"{prefix}_{src.name[:-4]}.heic"
            s, d = str(src), str(dst)
            if s not in known:
                untracked_masters.append(s)
                continue
            if not dst.is_file():
                unsynced.append(s)
                continue
            if times.get(s, 0) > times.get(d, 0):
                stale.append((s, d))

    drifted = bool(stale or unsynced or untracked_masters)

    if not args.quiet:
        if not drifted:
            print("✓ tile sets are in sync — every master has a current shipped tile")
        if stale:
            print(f"\n✗ {len(stale)} master(s) newer than the tile the app ships:")
            for s, d in stale[:40]:
                print(f"    {s}\n      → {d} is older")
            if len(stale) > 40:
                print(f"    … and {len(stale) - 40} more")
        if unsynced:
            print(f"\n✗ {len(unsynced)} master(s) with nothing in the bundle:")
            for s in unsynced[:20]:
                print(f"    {s}")
        if untracked_masters:
            print(f"\n! {len(untracked_masters)} master(s) not committed "
                  f"(cannot have been synced):")
            for s in untracked_masters[:20]:
                print(f"    {s}")
        if drifted:
            sets = sorted({Path(s).parent.name
                           for s, *_ in [(x,) if isinstance(x, str) else x
                                         for x in stale + unsynced + untracked_masters]})
            print("\nDrift must be intentional, not accidental. To ship these:")
            for folder in sets:
                print(f"    python3 tools/optimize_tiles.py --set {folder} --format heic")
                print(f"    python3 tools/sync_to_app.py --set {folder}")

    sys.exit(1 if drifted else 0)


if __name__ == "__main__":
    main()
