#!/usr/bin/env bash
# Converts the Apple HEIC tile art shipped in claudeBlast/TileImageSets/ into
# WebP for the web port. Requires ImageMagick with libheif + a HEVC decoder
# plugin (libheif-plugin-libde265 on Debian/Ubuntu).
set -euo pipefail

SRC="$(dirname "$0")/../../claudeBlast/TileImageSets"
DST="$(dirname "$0")/../assets/tiles"

mkdir -p "$DST"

count=0
total=$(ls "$SRC"/*.heic | wc -l)
for f in "$SRC"/*.heic; do
  base="$(basename "$f" .heic)"
  out="$DST/$base.webp"
  if [ -f "$out" ] && [ "$out" -nt "$f" ]; then
    continue
  fi
  magick "$f" -quality 85 "$out"
  count=$((count + 1))
  if (( count % 200 == 0 )); then
    echo "$count / $total converted"
  fi
done
echo "Done: $count converted (of $total total)."
