<!-- SPDX-License-Identifier: Apache-2.0 -->
# Blaster — Linux web port

A from-scratch reimplementation of [Blaster](https://github.com/marklucovsky/blasterai)'s
child-facing experience as a static, offline-capable web app, so it can run
on Linux (and be embedded in a kiosk-mode special-needs distro) instead of
iOS. Built following the upstream project's own [`docs/porting.md`](../docs/porting.md).

This is a rewrite, not a translation — SwiftUI/SwiftData/AVSpeechSynthesizer
don't run outside Apple platforms. What's carried over is the vocabulary,
scene structure, tile art, color system, and the AI sentence-generation
logic (prompt rules, caching, escalation, failure handling), all of which
were data or well-specified algorithms rather than Swift-specific code.

## Quick start

```bash
# One-time: decode the source HEIC art into web-friendly WebP.
# Needs ImageMagick with a HEIC/HEVC decoder (see below).
bash scripts/convert_tiles.sh

# Serve the app (any static file server works — this one needs no install).
python3 -m http.server 8080

# Open http://localhost:8080 in a browser.
```

No build step, no Node, no bundler — plain HTML/CSS/JS ES modules, so it
runs on whatever a minimal Linux install already has (`python3` or any
static file server) and is easy to vendor into a distro image.

### Image conversion prerequisite

The source art in `../claudeBlast/TileImageSets/*.heic` is Apple's HEIC
format, HEVC-coded. ImageMagick can decode it once the HEVC plugin is
installed:

```bash
sudo apt install libheif-plugin-libde265   # Debian/Ubuntu
```

`scripts/convert_tiles.sh` then converts all 2,797 tiles to WebP
(~85% quality) into `assets/tiles/`, named `{set_prefix}_{key}.webp` —
the same naming scheme as the source, so `data/image_sets.json` maps
directly to filenames.

## What's ported, and from where

| Piece | Source | Ported to |
|---|---|---|
| 508-word vocabulary | `../claudeBlast/Resources/vocabulary.json` | `data/vocabulary.json` (copied verbatim) |
| Default board (Core-First) | `../claudeBlast/Resources/scenes/core_first.json` | `data/scenes/core_first.json` (copied) + `js/sceneImporter.js` (the command-DSL interpreter, reimplemented from `SceneJSON.swift`) |
| Tile art, 5 styles | `../claudeBlast/TileImageSets/*.heic` | `assets/tiles/*.webp` (converted, not re-created) |
| Sentence system prompt | `../claudeBlast/Resources/sentence_prompt.json` | `data/sentence_prompt.json` (copied) |
| Prompt assembly, escalation ladder | `SentencePromptBuilder.swift` | `js/promptBuilder.js` |
| Brown's Stage descriptors | `ChildProfile.swift` | `js/brownsStage.js` |
| Cache key policy | `Engine/Cache/CacheKeyPolicy.swift` | `js/cacheKeyPolicy.js` |
| OpenAI failure classification | `Services/OpenAI/OpenAIFailure.swift` | `js/openai.js` |
| Sentence engine (debounce, staleness guard, escalation counting) | `Engine/SentenceEngine.swift` | `js/sentenceEngine.js` |
| Word→color (Modified Fitzgerald Key) | `Services/VocabularyClasses.swift` (`TileColorResolver`) | `js/color.js`, `data/vocabulary_classes.json` |
| Tile key normalization, art-alias resolution | `Models/TileModel.swift` | `js/model.js` |

## What's genuinely different from the iOS app

- **TTS**: `AVSpeechSynthesizer` → the browser's Web Speech API
  (`speechSynthesis`). On Linux this is typically backed by
  speech-dispatcher/espeak-ng via the browser, so voice quality depends on
  what the distro ships — steer users toward the best installed voice, same
  advice as upstream.
- **Persistence**: SwiftData/CloudKit → `localStorage` (settings + sentence
  cache only, single device, no sync) — deliberately the simplest option
  upstream recommends for "a Linux laptop that lives on one desk"
  (`docs/porting.md` §3).
- **Grid layout**: the iOS app computes an exact tile size/column/row count
  per device (`GridLayoutCalculator`) and paginates. The web version uses a
  responsive CSS grid (`auto-fill`/`minmax`) that wraps and scrolls instead
  — simpler, and idiomatic for a browser, at the cost of exact pixel/page
  parity.
- **Secrets**: an OpenAI key typed into Settings lives in `localStorage`,
  same trust model as the iOS app's `UserDefaults` storage (dev-appropriate,
  not Keychain-grade).

## Known gaps (not yet ported)

- **PIN-gated admin / hidden triple-tap menu.** Settings are reachable via a
  visible gear icon, not hidden behind a caregiver gesture.
- **Caregiver overrides & suppression.** The "block this word combination
  forever" and "hand-typed correction always wins" rules from
  `SentenceEngine.swift` step 1 and step 3 aren't implemented — sentence
  mode always goes cache → model.
- **Word moderation** (`WordModerationService.swift`'s three-layer check) —
  not applicable yet since there's no runtime "add a word" flow.
- **OBF import/export.** Upstream calls this "the single highest-value thing
  you can implement early" (`docs/porting.md` §8) — not started. Worth doing
  next so boards can move between this app, Cboard, CoughDrop, etc.
- **Vocabulary packs, alternate/multiple scenes, scene editor.** Only the
  single default `core_first` scene is wired up.
- **Replay history sheet, session notes.** The tray has replay/clear only.

## Integrating into a Linux distro (kiosk mode)

This is a static site, so any of these work:

1. **Browser kiosk mode**, autostarted: point a browser at
   `http://localhost:8080` (served by a small systemd unit running
   `python3 -m http.server` from this directory) with `--kiosk` /
   `--app=` flags, launched from the distro's session autostart.
2. **A minimal Electron/Tauri/webview wrapper**, if you want a dock icon and
   window chrome instead of a bare kiosk browser.
3. **Vendor as-is into a distro image** — the whole `web/` directory (plus
   `assets/tiles/` once converted) is self-contained; nothing calls out to a
   backend except OpenAI, and only when sentence mode + a key are configured.

None of this is wired up yet — happy to build the systemd unit + autostart
config once you've picked which of the above fits your distro's init system
and desktop environment.
